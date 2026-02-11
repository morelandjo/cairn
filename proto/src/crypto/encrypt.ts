/**
 * Message encryption helpers for the Murmuring protocol.
 *
 * Provides high-level encrypt/decrypt functions that use the Double Ratchet
 * to produce EncryptedPayload objects conforming to the wire format.
 */

import type { DoubleRatchet } from "./ratchet.js";
import type { EncryptedPayload } from "../types.js";

/**
 * Encrypt a plaintext message using the Double Ratchet.
 *
 * @param ratchet - The Double Ratchet session with the peer
 * @param plaintext - The plaintext string or bytes to encrypt
 * @returns An EncryptedPayload with header, ciphertext, and nonce
 */
export async function encryptMessage(
  ratchet: DoubleRatchet,
  plaintext: string | Uint8Array,
): Promise<EncryptedPayload> {
  const plaintextBytes =
    typeof plaintext === "string" ? new TextEncoder().encode(plaintext) : plaintext;

  const { header, ciphertext, nonce } = await ratchet.encrypt(plaintextBytes);

  return {
    header,
    ciphertext,
    nonce,
  };
}

/**
 * Decrypt an EncryptedPayload using the Double Ratchet.
 *
 * @param ratchet - The Double Ratchet session with the peer
 * @param payload - The EncryptedPayload to decrypt
 * @returns The decrypted plaintext as a Uint8Array
 */
export async function decryptMessage(
  ratchet: DoubleRatchet,
  payload: EncryptedPayload,
): Promise<Uint8Array> {
  return ratchet.decrypt(payload.header, payload.ciphertext, payload.nonce);
}
