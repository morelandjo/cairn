/**
 * Extended Triple Diffie-Hellman (X3DH) key agreement protocol.
 *
 * X3DH establishes a shared secret between two parties (Alice and Bob) even
 * when Bob is offline. Alice uses Bob's published key bundle to compute the
 * shared secret, and Bob can later compute the same secret upon receiving
 * Alice's initial message.
 *
 * DH computations use X25519. Since identity keys are Ed25519, they are
 * converted to X25519 (Curve25519) for the DH operations.
 *
 * The four DH exchanges are:
 *   DH1 = DH(IK_A, SPK_B) — Alice's identity, Bob's signed pre-key
 *   DH2 = DH(EK_A, IK_B)  — Alice's ephemeral, Bob's identity
 *   DH3 = DH(EK_A, SPK_B) — Alice's ephemeral, Bob's signed pre-key
 *   DH4 = DH(EK_A, OPK_B) — Alice's ephemeral, Bob's one-time pre-key (optional)
 *
 * The shared secret is derived via HKDF-SHA-256 over the concatenated DH outputs.
 */

import { ensureSodium } from "./keys.js";
import type { IdentityKeyPair, KeyBundle } from "../types.js";

/** Info string used in HKDF derivation */
const HKDF_INFO = "cairn-x3dh-v1";

/** Length of the derived shared secret in bytes */
const SHARED_SECRET_LENGTH = 32;

/**
 * HKDF-SHA-256: Extract-then-Expand.
 *
 * Implemented using HMAC-SHA-256 from libsodium (crypto_auth_hmacsha256).
 *
 * @param salt - Optional salt (if empty, uses a zero-filled key of hash length)
 * @param ikm - Input keying material
 * @param info - Context/application-specific info string
 * @param length - Desired output length in bytes (max 255 * 32)
 */
async function hkdf(
  salt: Uint8Array,
  ikm: Uint8Array,
  info: string,
  length: number,
): Promise<Uint8Array> {
  const s = await ensureSodium();

  // Extract: PRK = HMAC-SHA-256(salt, IKM)
  const saltKey = salt.length > 0 ? salt : new Uint8Array(32);
  const prk = s.crypto_auth_hmacsha256(ikm, saltKey);

  // Expand: Output = T(1) || T(2) || ... where T(i) = HMAC-SHA-256(PRK, T(i-1) || info || i)
  const infoBytes = s.from_string(info);
  const n = Math.ceil(length / 32);
  const okm = new Uint8Array(n * 32);
  let prev = new Uint8Array(0);

  for (let i = 1; i <= n; i++) {
    const input = new Uint8Array(prev.length + infoBytes.length + 1);
    input.set(prev, 0);
    input.set(infoBytes, prev.length);
    input[prev.length + infoBytes.length] = i;
    const t = s.crypto_auth_hmacsha256(input, prk);
    okm.set(t, (i - 1) * 32);
    prev = new Uint8Array(t);
  }

  return okm.slice(0, length);
}

/**
 * Convert an Ed25519 public key to an X25519 public key.
 */
async function ed25519PkToX25519(ed25519Pk: Uint8Array): Promise<Uint8Array> {
  const s = await ensureSodium();
  return s.crypto_sign_ed25519_pk_to_curve25519(ed25519Pk);
}

/**
 * Convert an Ed25519 secret key to an X25519 secret key.
 */
async function ed25519SkToX25519(ed25519Sk: Uint8Array): Promise<Uint8Array> {
  const s = await ensureSodium();
  return s.crypto_sign_ed25519_sk_to_curve25519(ed25519Sk);
}

/**
 * Perform an X25519 Diffie-Hellman key exchange.
 *
 * @param privateKey - Our X25519 private key (32 bytes)
 * @param publicKey - Peer's X25519 public key (32 bytes)
 * @returns The shared DH output (32 bytes)
 */
async function dh(privateKey: Uint8Array, publicKey: Uint8Array): Promise<Uint8Array> {
  const s = await ensureSodium();
  return s.crypto_scalarmult(privateKey, publicKey);
}

/** Result of an X3DH initiation */
export interface X3DHInitResult {
  /** The derived shared secret (32 bytes) */
  sharedSecret: Uint8Array;
  /** The ephemeral public key Alice sends to Bob */
  ephemeralPublicKey: Uint8Array;
}

/**
 * Initiator side of X3DH (Alice).
 *
 * Alice fetches Bob's key bundle and computes the shared secret.
 * She also generates an ephemeral key pair for forward secrecy.
 *
 * @param identityKeyPair - Alice's Ed25519 identity key pair
 * @param peerBundle - Bob's published key bundle
 * @returns The shared secret and ephemeral public key to send to Bob
 */
export async function x3dhInitiate(
  identityKeyPair: IdentityKeyPair,
  peerBundle: KeyBundle,
): Promise<X3DHInitResult> {
  const s = await ensureSodium();

  // Verify Bob's signed pre-key signature
  const valid = s.crypto_sign_verify_detached(
    peerBundle.signedPreKeySignature,
    peerBundle.signedPreKey,
    peerBundle.identityKey,
  );
  if (!valid) {
    throw new Error("X3DH: Invalid signed pre-key signature");
  }

  // Convert Alice's Ed25519 identity key to X25519
  const aliceIdentityX25519Sk = await ed25519SkToX25519(identityKeyPair.privateKey);

  // Convert Bob's Ed25519 identity key to X25519
  const bobIdentityX25519Pk = await ed25519PkToX25519(peerBundle.identityKey);

  // Generate ephemeral X25519 key pair
  const ephemeralKeyPair = s.crypto_box_keypair();

  // Compute the four DH exchanges
  const dh1 = await dh(aliceIdentityX25519Sk, peerBundle.signedPreKey);
  const dh2 = await dh(ephemeralKeyPair.privateKey, bobIdentityX25519Pk);
  const dh3 = await dh(ephemeralKeyPair.privateKey, peerBundle.signedPreKey);

  // Concatenate DH results
  let dhConcat: Uint8Array;
  if (peerBundle.oneTimePreKey) {
    const dh4 = await dh(ephemeralKeyPair.privateKey, peerBundle.oneTimePreKey);
    dhConcat = new Uint8Array(dh1.length + dh2.length + dh3.length + dh4.length);
    dhConcat.set(dh1, 0);
    dhConcat.set(dh2, dh1.length);
    dhConcat.set(dh3, dh1.length + dh2.length);
    dhConcat.set(dh4, dh1.length + dh2.length + dh3.length);
  } else {
    dhConcat = new Uint8Array(dh1.length + dh2.length + dh3.length);
    dhConcat.set(dh1, 0);
    dhConcat.set(dh2, dh1.length);
    dhConcat.set(dh3, dh1.length + dh2.length);
  }

  // Derive shared secret with HKDF
  // Use a salt of 32 zero bytes (as per Signal spec)
  const salt = new Uint8Array(32);
  const sharedSecret = await hkdf(salt, dhConcat, HKDF_INFO, SHARED_SECRET_LENGTH);

  return {
    sharedSecret,
    ephemeralPublicKey: ephemeralKeyPair.publicKey,
  };
}

/**
 * Responder side of X3DH (Bob).
 *
 * Bob receives Alice's initial message containing her identity key and
 * ephemeral public key, and computes the same shared secret.
 *
 * @param identityKeyPair - Bob's Ed25519 identity key pair
 * @param signedPreKeyPrivate - Bob's signed pre-key private key (X25519, 32 bytes)
 * @param oneTimePreKeyPrivate - Bob's one-time pre-key private key, if one was used
 * @param peerIdentityKey - Alice's Ed25519 identity public key
 * @param ephemeralKey - Alice's ephemeral X25519 public key
 * @returns The derived shared secret (32 bytes)
 */
export async function x3dhRespond(
  identityKeyPair: IdentityKeyPair,
  signedPreKeyPrivate: Uint8Array,
  oneTimePreKeyPrivate: Uint8Array | null,
  peerIdentityKey: Uint8Array,
  ephemeralKey: Uint8Array,
): Promise<Uint8Array> {
  // Convert Bob's Ed25519 identity key to X25519
  const bobIdentityX25519Sk = await ed25519SkToX25519(identityKeyPair.privateKey);

  // Convert Alice's Ed25519 identity key to X25519
  const aliceIdentityX25519Pk = await ed25519PkToX25519(peerIdentityKey);

  // Compute the four DH exchanges (mirror of Alice's computation)
  const dh1 = await dh(signedPreKeyPrivate, aliceIdentityX25519Pk);
  const dh2 = await dh(bobIdentityX25519Sk, ephemeralKey);
  const dh3 = await dh(signedPreKeyPrivate, ephemeralKey);

  // Concatenate DH results
  let dhConcat: Uint8Array;
  if (oneTimePreKeyPrivate) {
    const dh4 = await dh(oneTimePreKeyPrivate, ephemeralKey);
    dhConcat = new Uint8Array(dh1.length + dh2.length + dh3.length + dh4.length);
    dhConcat.set(dh1, 0);
    dhConcat.set(dh2, dh1.length);
    dhConcat.set(dh3, dh1.length + dh2.length);
    dhConcat.set(dh4, dh1.length + dh2.length + dh3.length);
  } else {
    dhConcat = new Uint8Array(dh1.length + dh2.length + dh3.length);
    dhConcat.set(dh1, 0);
    dhConcat.set(dh2, dh1.length);
    dhConcat.set(dh3, dh1.length + dh2.length);
  }

  // Derive shared secret with HKDF
  const salt = new Uint8Array(32);
  const sharedSecret = await hkdf(salt, dhConcat, HKDF_INFO, SHARED_SECRET_LENGTH);

  return sharedSecret;
}

/** Export hkdf for internal use by the ratchet module */
export { hkdf };
