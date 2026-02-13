/**
 * Voice E2E encryption using Insertable Streams (Encoded Transforms).
 *
 * Derives AES-128-GCM keys from MLS epoch secrets using HKDF.
 * Frame format: [IV 12 bytes] [AES-128-GCM encrypted payload] [GCM tag 16 bytes]
 */

const VOICE_KEY_INFO = new TextEncoder().encode("cairn-voice-key");
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const KEY_LENGTH = 16; // AES-128

/**
 * Derive a voice encryption key from an MLS epoch secret using HKDF.
 */
export async function deriveVoiceKey(
  epochSecret: Uint8Array,
): Promise<CryptoKey> {
  const baseKey = await crypto.subtle.importKey(
    "raw",
    epochSecret as BufferSource,
    "HKDF",
    false,
    ["deriveKey"],
  );

  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(32), // Zero salt for simplicity
      info: VOICE_KEY_INFO,
    },
    baseKey,
    { name: "AES-GCM", length: KEY_LENGTH * 8 },
    false,
    ["encrypt", "decrypt"],
  );
}

/**
 * Encrypt a single media frame.
 * Returns: [IV (12)] [encrypted data] [GCM tag (16)]
 */
export async function encryptFrame(
  key: CryptoKey,
  data: Uint8Array,
): Promise<Uint8Array> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));

  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, tagLength: TAG_LENGTH * 8 },
    key,
    data as BufferSource,
  );

  const result = new Uint8Array(IV_LENGTH + encrypted.byteLength);
  result.set(iv, 0);
  result.set(new Uint8Array(encrypted), IV_LENGTH);
  return result;
}

/**
 * Decrypt a single media frame.
 * Input: [IV (12)] [encrypted data + GCM tag (16)]
 */
export async function decryptFrame(
  key: CryptoKey,
  data: Uint8Array,
): Promise<Uint8Array> {
  if (data.length < IV_LENGTH + TAG_LENGTH) {
    throw new Error("Frame too short to decrypt");
  }

  const iv = data.slice(0, IV_LENGTH);
  const ciphertext = data.slice(IV_LENGTH);

  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, tagLength: TAG_LENGTH * 8 },
    key,
    ciphertext as BufferSource,
  );

  return new Uint8Array(decrypted);
}

/**
 * Check if the browser supports Insertable Streams / Encoded Transforms.
 */
export function supportsInsertableStreams(): boolean {
  return (
    typeof RTCRtpSender !== "undefined" &&
    "createEncodedStreams" in RTCRtpSender.prototype
  ) || (
    typeof RTCRtpSender !== "undefined" &&
    "transform" in RTCRtpSender.prototype
  );
}

/**
 * Create a TransformStream that encrypts RTC encoded frames.
 */
export function createEncryptTransform(
  key: CryptoKey,
): TransformStream {
  return new TransformStream({
    async transform(encodedFrame: RTCEncodedAudioFrame | RTCEncodedVideoFrame, controller) {
      try {
        const data = new Uint8Array(encodedFrame.data);
        const encrypted = await encryptFrame(key, data);
        encodedFrame.data = encrypted.buffer as ArrayBuffer;
        controller.enqueue(encodedFrame);
      } catch {
        // On encryption failure, pass through (best effort)
        controller.enqueue(encodedFrame);
      }
    },
  });
}

/**
 * Create a TransformStream that decrypts RTC encoded frames.
 * Supports a transition window with an old key for key rotation.
 */
export function createDecryptTransform(
  key: CryptoKey,
  oldKey?: CryptoKey,
): TransformStream {
  return new TransformStream({
    async transform(encodedFrame: RTCEncodedAudioFrame | RTCEncodedVideoFrame, controller) {
      const data = new Uint8Array(encodedFrame.data);

      try {
        const decrypted = await decryptFrame(key, data);
        encodedFrame.data = decrypted.buffer as ArrayBuffer;
        controller.enqueue(encodedFrame);
      } catch {
        // Try old key during rotation transition
        if (oldKey) {
          try {
            const decrypted = await decryptFrame(oldKey, data);
            encodedFrame.data = decrypted.buffer as ArrayBuffer;
            controller.enqueue(encodedFrame);
            return;
          } catch {
            // Both keys failed
          }
        }
        // Pass through undecrypted (will sound garbled, better than silence)
        controller.enqueue(encodedFrame);
      }
    },
  });
}
