import { createHash, createDecipheriv } from 'crypto';
import type { ApiResponse } from './streammafia.types.ts';

function base64ToBuffer(b64: string): Buffer {
    return Buffer.from(b64, 'base64');
}

function deriveKey(secret: string): Buffer {
    return createHash('sha256').update(secret).digest();
}

export function decryptStreamMafia(payload: {
    iv: string;
    tag: string;
    data: string;
}): ApiResponse {
    try {
        const iv = base64ToBuffer(payload.iv);
        const tag = base64ToBuffer(payload.tag);
        const data = base64ToBuffer(payload.data);

        const key = deriveKey('Z9#rL!v2K*5qP&7mXw');

        const decipher = createDecipheriv('aes-256-gcm', key, iv);

        // attach auth tag
        decipher.setAuthTag(tag);

        const decrypted = Buffer.concat([
            decipher.update(data),
            decipher.final()
        ]);

        const jsonString = decrypted.toString('utf-8');

        if (!jsonString) {
            throw new Error('Empty decrypted result');
        }

        return JSON.parse(jsonString);
    } catch (err) {
        throw new Error('Failed to decrypt StreamMafia response');
    }
}
