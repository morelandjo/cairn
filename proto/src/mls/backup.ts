/**
 * Encrypted key backup — export/import all crypto keys encrypted with a passphrase.
 *
 * Uses Argon2id for key derivation and XChaCha20-Poly1305 for encryption.
 * The encrypted format is:
 *   version(1 byte) || salt(16 bytes) || nonce(24 bytes) || ciphertext(variable)
 *
 * The plaintext is JSON-encoded with binary fields represented as base64.
 */

import sodium from "libsodium-wrappers-sumo";
import { ensureSodium } from "../crypto/index.js";

const BACKUP_VERSION = 1;
const SALT_BYTES = 16;

// Argon2id parameters — INTERACTIVE level for browser compatibility.
// (MODERATE = 256MB/3 iter is too heavy for mobile browsers.)
const ARGON2_OPSLIMIT = 2; // OPSLIMIT_INTERACTIVE
const ARGON2_MEMLIMIT = 67108864; // MEMLIMIT_INTERACTIVE (64MB)

/**
 * Payload structure for key backups.
 * Binary fields are base64-encoded in the JSON representation.
 */
export interface KeyBackupPayload {
  /** Ed25519 identity key pair */
  identityKeyPair?: {
    publicKey: string; // base64
    privateKey: string; // base64
  };
  /** Signed pre-key */
  signedPreKey?: {
    keyId: number;
    publicKey: string;
    privateKey: string;
    signature: string;
    timestamp: number;
  };
  /** One-time pre-keys */
  oneTimePreKeys?: Array<{
    keyId: number;
    publicKey: string;
    privateKey: string;
  }>;
  /** MLS credential */
  mlsCredential?: {
    identity: string;
    signingPublicKey: string;
    signingPrivateKey: string;
  };
  /** Arbitrary additional data */
  [key: string]: unknown;
}

/**
 * Encrypt a key backup payload with a passphrase.
 *
 * @param payload - The key backup data to encrypt
 * @param passphrase - User-provided passphrase for encryption
 * @returns Encrypted backup as Uint8Array
 */
export async function exportKeys(
  payload: KeyBackupPayload,
  passphrase: string,
): Promise<Uint8Array> {
  const s = await ensureSodium();

  // Serialize payload to JSON bytes
  const plaintext = s.from_string(JSON.stringify(payload));

  // Generate random salt and nonce
  const salt = s.randombytes_buf(SALT_BYTES);
  const nonce = s.randombytes_buf(
    s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES,
  );

  // Derive encryption key from passphrase using Argon2id
  const key = s.crypto_pwhash(
    s.crypto_aead_xchacha20poly1305_ietf_KEYBYTES,
    passphrase,
    salt,
    ARGON2_OPSLIMIT,
    ARGON2_MEMLIMIT,
    s.crypto_pwhash_ALG_ARGON2ID13,
  );

  // Encrypt with XChaCha20-Poly1305
  const ciphertext = s.crypto_aead_xchacha20poly1305_ietf_encrypt(
    plaintext,
    null, // no additional data
    null, // no secret nonce
    nonce,
    key,
  );

  // Pack: version || salt || nonce || ciphertext
  const result = new Uint8Array(1 + salt.length + nonce.length + ciphertext.length);
  result[0] = BACKUP_VERSION;
  result.set(salt, 1);
  result.set(nonce, 1 + salt.length);
  result.set(ciphertext, 1 + salt.length + nonce.length);

  return result;
}

/**
 * Decrypt a key backup with a passphrase.
 *
 * @param encrypted - The encrypted backup bytes
 * @param passphrase - The passphrase used during export
 * @returns The decrypted key backup payload
 * @throws Error if passphrase is wrong or data is corrupted
 */
export async function importKeys(
  encrypted: Uint8Array,
  passphrase: string,
): Promise<KeyBackupPayload> {
  const s = await ensureSodium();

  if (encrypted.length < 1 + SALT_BYTES + s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES + s.crypto_aead_xchacha20poly1305_ietf_ABYTES) {
    throw new Error("Backup data too short");
  }

  const version = encrypted[0];
  if (version !== BACKUP_VERSION) {
    throw new Error(`Unsupported backup version: ${version}`);
  }

  // Unpack: version || salt || nonce || ciphertext
  let offset = 1;
  const salt = encrypted.slice(offset, offset + SALT_BYTES);
  offset += SALT_BYTES;

  const nonceLen = s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES;
  const nonce = encrypted.slice(offset, offset + nonceLen);
  offset += nonceLen;

  const ciphertext = encrypted.slice(offset);

  // Re-derive key from passphrase
  const key = s.crypto_pwhash(
    s.crypto_aead_xchacha20poly1305_ietf_KEYBYTES,
    passphrase,
    salt,
    ARGON2_OPSLIMIT,
    ARGON2_MEMLIMIT,
    s.crypto_pwhash_ALG_ARGON2ID13,
  );

  // Decrypt
  const plaintext = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
    null, // no secret nonce
    ciphertext,
    null, // no additional data
    nonce,
    key,
  );

  return JSON.parse(s.to_string(plaintext)) as KeyBackupPayload;
}
