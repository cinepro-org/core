import type { klikxxiResponse } from './vidnest.types.ts';

/**
 * Custom alphabet taken from VidNest frontend logic.
 */
const VIDNEST_ALPHABET =
    'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';

/**
 * Precomputed lookup map from character -> numeric value (0..63),
 * unknown characters map to 64 as a sentinel.
 */
const VIDNEST_REVERSE_MAP: Record<string, number> = (() => {
    const map: Record<string, number> = {};
    for (let i = 0; i < VIDNEST_ALPHABET.length; i++) {
        map[VIDNEST_ALPHABET[i]!] = i;
    }
    return map;
})();

/**
 * Decode a VidNest custom-base64 encoded string into a UTF-8 string.
 */
export function decodeVidnestBase64(input: string): string {
    if (!input || typeof input !== 'string') {
        throw new Error('VidNest: invalid payload, expected non-empty string');
    }

    // Pad globally to a multiple of 4, mirroring the browser logic
    let padded = input;
    const mod = padded.length % 4;
    if (mod !== 0) {
        padded += '='.repeat(4 - mod);
    }

    const bytes: number[] = [];

    for (let i = 0; i < padded.length; i += 4) {
        const chunk = padded.slice(i, i + 4);

        let c0 = VIDNEST_REVERSE_MAP[chunk[0]!] ?? 64;
        let c1 = VIDNEST_REVERSE_MAP[chunk[1]!] ?? 64;
        let c2 = chunk[2] === '=' ? 64 : (VIDNEST_REVERSE_MAP[chunk[2]!] ?? 64);
        let c3 = chunk[3] === '=' ? 64 : (VIDNEST_REVERSE_MAP[chunk[3]!] ?? 64);

        // 1st byte: (c0 << 2) | (c1 >> 4)
        bytes.push(((c0 << 2) | (c1 >> 4)) & 0xff);

        // 2nd byte: ((c1 & 15) << 4) | (c2 >> 2)
        if (c2 !== 64) {
            bytes.push((((c1 & 0x0f) << 4) | (c2 >> 2)) & 0xff);
        }

        // 3rd byte: ((c2 & 3) << 6) | c3
        if (c3 !== 64) {
            bytes.push((((c2 & 0x03) << 6) | c3) & 0xff);
        }
    }

    const decoder = new TextDecoder();
    return decoder.decode(new Uint8Array(bytes));
}

export default function decrypt<T>(payload: string): T {
    try {
        const decoded = JSON.parse(decodeVidnestBase64(payload));
        return decoded as T;
    } catch {
        throw new Error('VidNest: failed to parse decrypted payload as JSON');
    }
}
