import { webcrypto } from 'crypto';
import type { PeachifyApiResponse } from './peachify.types.ts';

const { subtle } = webcrypto;

const ENCRYPTION_KEY_HEX =
    'YThmMmExYjVlOWM0NzA4MTRmNmIyYzNhNWQ4ZTdmOWMxYTJiM2M0ZDVlM2Y3YThiOGNhZDFlMmQwYTRkNWM1Yg==';

/**
 * Peachify payload format:
 *
 *   base64url(iv).base64url(ciphertext).base64url(authTag)
 *
 * AES-GCM expects ciphertext + authTag combined into a single buffer.
 */
type EncryptedPayload = {
    iv: Uint8Array;
    ciphertext: Uint8Array;
    authTag: Uint8Array;
};

/**
 * Convert a base64url string into bytes.
 */
function base64UrlToBytes(value: string): Uint8Array {
    const base64 = value.replace(/-/g, '+').replace(/_/g, '/');

    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');

    const binary = Buffer.from(padded, 'base64');

    return new Uint8Array(binary);
}

/**
 * Convert a hex string into bytes.
 */
function hexToBytes(hex: string): Uint8Array {
    if (hex.length % 2 !== 0) {
        throw new Error('Invalid hex string length');
    }

    const bytes = new Uint8Array(hex.length / 2);

    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
    }

    return bytes;
}

/**
 * Import the AES-GCM decryption key.
 */
async function importDecryptionKey(): Promise<webcrypto.CryptoKey> {
    return subtle.importKey(
        'raw',
        hexToBytes(Buffer.from(ENCRYPTION_KEY_HEX, 'base64').toString()),
        { name: 'AES-GCM' },
        false,
        ['decrypt']
    );
}

/**
 * Parse the encrypted Peachify payload.
 */
function parsePayload(payload: string): EncryptedPayload {
    const parts = payload.split('.');

    if (parts.length !== 3) {
        throw new Error(
            'Invalid payload format. Expected: iv.ciphertext.authTag'
        );
    }

    const [ivPart, ciphertextPart, authTagPart] = parts;

    return {
        iv: base64UrlToBytes(ivPart),
        ciphertext: base64UrlToBytes(ciphertextPart),
        authTag: base64UrlToBytes(authTagPart)
    };
}

/**
 * Decrypt a Peachify API response payload.
 */
export default async function decryptPayload(
    payload: string
): Promise<PeachifyApiResponse | null> {
    try {
        if (process.env.NUVIO_ENV) {
          // Nuvio does not support certain features, so handle it this way.
          const result = await fetch('https://enc-dec.app/api/dec-peachify', {
            method: 'POST',
            body: JSON.stringify({
              text: payload,
            }),
          });
          return (await result.json() as any).result;
        }
        const { iv, ciphertext, authTag } = parsePayload(payload);

        // AES-GCM expects ciphertext + auth tag concatenated.
        const encryptedData = new Uint8Array(
            ciphertext.length + authTag.length
        );

        encryptedData.set(ciphertext);
        encryptedData.set(authTag, ciphertext.length);

        const key = await importDecryptionKey();

        const decryptedBuffer = await subtle.decrypt(
            {
                name: 'AES-GCM',
                iv
            },
            key,
            encryptedData
        );

        const decryptedJson = new TextDecoder().decode(decryptedBuffer);

        return JSON.parse(decryptedJson) as PeachifyApiResponse;
    } catch (error) {
        return null;
    }
}
