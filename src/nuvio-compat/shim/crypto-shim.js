import CryptoJS from 'crypto-js';

function wordArrayToUint8Array(wordArray) {
  const { words, sigBytes } = wordArray;
  const result = new Uint8Array(sigBytes);

  for (let i = 0; i < sigBytes; i++) {
    result[i] = (words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
  }

  return Buffer.from(result);
}

function uint8ArrayToWordArray(u8arr) {
  const words = [];

  for (let i = 0; i < u8arr.length; i++) {
    words[i >>> 2] |= u8arr[i] << (24 - (i % 4) * 8);
  }

  return CryptoJS.lib.WordArray.create(words, u8arr.length);
}

function normalizeBuffer(input) {
  if (input instanceof Uint8Array) {
    return input;
  }

  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer);
  }

  if (input instanceof ArrayBuffer) {
    return new Uint8Array(input);
  }

  if (typeof input === 'string') {
    return new TextEncoder().encode(input);
  }

  throw new TypeError('Unsupported input type');
}

function getAesMode(mode) {
  switch (mode.toLowerCase()) {
    case 'cbc':
      return CryptoJS.mode.CBC;
    case 'ecb':
      return CryptoJS.mode.ECB;
    case 'cfb':
      return CryptoJS.mode.CFB;
    case 'ctr':
      return CryptoJS.mode.CTR;
    case 'ofb':
      return CryptoJS.mode.OFB;
    default:
      throw new Error(`Unsupported AES mode: ${mode}`);
  }
}

function getPadding(padding = 'Pkcs7') {
  switch (padding.toLowerCase()) {
    case 'pkcs7':
      return CryptoJS.pad.Pkcs7;
    case 'nopadding':
      return CryptoJS.pad.NoPadding;
    default:
      throw new Error(`Unsupported padding: ${padding}`);
  }
}

export function createHash(algorithm) {
  const chunks = [];

  return {
    update(data) {
      chunks.push(normalizeBuffer(data));
      return this;
    },

    digest(encoding) {
      const total = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
      const merged = new Uint8Array(total);

      let offset = 0;

      for (const chunk of chunks) {
        merged.set(chunk, offset);
        offset += chunk.length;
      }

      const wordArray = uint8ArrayToWordArray(merged);

      let hash;

      switch (algorithm.toLowerCase()) {
        case 'sha1':
          hash = CryptoJS.SHA1(wordArray);
          break;
        case 'sha256':
          hash = CryptoJS.SHA256(wordArray);
          break;
        case 'sha512':
          hash = CryptoJS.SHA512(wordArray);
          break;
        case 'md5':
          hash = CryptoJS.MD5(wordArray);
          break;
        default:
          throw new Error(`Unsupported hash algorithm: ${algorithm}`);
      }

      if (encoding === 'hex') {
        return hash.toString(CryptoJS.enc.Hex);
      }

      return wordArrayToUint8Array(hash);
    },
  };
}

export function createDecipheriv(algorithm, key, iv) {
  const [cipher, bits, mode] = algorithm.toLowerCase().split('-');

  if (cipher !== 'aes') {
    throw new Error(`Unsupported cipher: ${cipher}`);
  }

  const cryptoKey = uint8ArrayToWordArray(normalizeBuffer(key));
  const cryptoIv = uint8ArrayToWordArray(normalizeBuffer(iv));

  const chunks = [];

  return {
    update(data) {
      chunks.push(normalizeBuffer(data));
      // Nothing yet.
      return Buffer.from([]);
    },

    final(outputEncoding) {
      const total = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
      const merged = new Uint8Array(total);

      let offset = 0;

      for (const chunk of chunks) {
        merged.set(chunk, offset);
        offset += chunk.length;
      }

      const encrypted = uint8ArrayToWordArray(merged);

      const decrypted = CryptoJS.AES.decrypt(
        {
          ciphertext: encrypted,
        },
        cryptoKey,
        {
          iv: cryptoIv,
          mode: getAesMode(mode),
          padding: CryptoJS.pad.Pkcs7,
        },
      );

      if (outputEncoding === 'utf8') {
        return decrypted.toString(CryptoJS.enc.Utf8);
      }

      return wordArrayToUint8Array(decrypted);
    },
  };
}

export const webcrypto = {
  subtle: {
    async importKey(format, keyData, algorithm, extractable, keyUsages) {
      return {
        type: 'secret',
        algorithm,
        extractable,
        usages: keyUsages,
        keyData: normalizeBuffer(keyData),
      };
    },

    async encrypt(algorithm, key, data) {
      const algoName = algorithm.name.toUpperCase();

      if (algoName !== 'AES-CBC') {
        throw new Error(`Unsupported algorithm: ${algoName}`);
      }

      const cryptoKey = uint8ArrayToWordArray(key.keyData);
      const cryptoIv = uint8ArrayToWordArray(
        normalizeBuffer(algorithm.iv),
      );

      const plaintext = uint8ArrayToWordArray(
        normalizeBuffer(data),
      );

      const encrypted = CryptoJS.AES.encrypt(
        plaintext,
        cryptoKey,
        {
          iv: cryptoIv,
          mode: CryptoJS.mode.CBC,
          padding: CryptoJS.pad.Pkcs7,
        },
      );

      return wordArrayToUint8Array(
        encrypted.ciphertext,
      );
    },

    async decrypt(algorithm, key, data) {
      const algoName = algorithm.name.toUpperCase();

      if (algoName !== 'AES-CBC') {
        throw new Error(`Unsupported algorithm: ${algoName}`);
      }

      const cryptoKey = uint8ArrayToWordArray(key.keyData);
      const cryptoIv = uint8ArrayToWordArray(
        normalizeBuffer(algorithm.iv),
      );

      const ciphertext = uint8ArrayToWordArray(
        normalizeBuffer(data),
      );

      const decrypted = CryptoJS.AES.decrypt(
        {
          ciphertext,
        },
        cryptoKey,
        {
          iv: cryptoIv,
          mode: CryptoJS.mode.CBC,
          padding: CryptoJS.pad.Pkcs7,
        },
      );

      return wordArrayToUint8Array(decrypted);
    },

    async digest(algorithm, data) {
      const normalized =
        typeof algorithm === 'string'
          ? algorithm.toLowerCase()
          : algorithm.name.toLowerCase();

      const wordArray = uint8ArrayToWordArray(
        normalizeBuffer(data),
      );

      let hash;

      switch (normalized) {
        case 'sha-1':
        case 'sha1':
          hash = CryptoJS.SHA1(wordArray);
          break;

        case 'sha-256':
        case 'sha256':
          hash = CryptoJS.SHA256(wordArray);
          break;

        case 'sha-512':
        case 'sha512':
          hash = CryptoJS.SHA512(wordArray);
          break;

        default:
          throw new Error(
            `Unsupported digest algorithm: ${algorithm}`,
          );
      }

      return wordArrayToUint8Array(hash);
    },
  },
};

export default { createHash, createDecipheriv, webcrypto };
