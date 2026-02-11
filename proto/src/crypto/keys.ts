/**
 * Key generation functions for the Murmuring E2EE protocol.
 *
 * Uses libsodium for all cryptographic operations:
 * - Ed25519 for identity keys (signing)
 * - X25519 for ephemeral/pre-keys (Diffie-Hellman)
 */

import sodium from "libsodium-wrappers-sumo";
import type { IdentityKeyPair, SignedPreKey, OneTimePreKey } from "../types.js";

/**
 * Ensure libsodium is initialized before use.
 * Safe to call multiple times; only initializes once.
 */
export async function ensureSodium(): Promise<typeof sodium> {
  await sodium.ready;
  return sodium;
}

/**
 * Generate an Ed25519 identity key pair for long-term signing.
 *
 * The identity key pair is the root of trust for a user. The public key
 * is published and used by peers to verify signatures on pre-keys and
 * messages.
 */
export async function generateIdentityKeyPair(): Promise<IdentityKeyPair> {
  const s = await ensureSodium();
  const keyPair = s.crypto_sign_keypair();
  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    keyType: "ed25519",
  };
}

/**
 * Generate a signed pre-key (X25519) and sign it with the identity key.
 *
 * The signed pre-key is a medium-term X25519 key pair. Its public key is
 * signed with the identity key so that peers can verify its authenticity.
 *
 * @param identityKeyPair - The signer's Ed25519 identity key pair
 * @param keyId - Unique identifier for this signed pre-key
 */
export async function generateSignedPreKey(
  identityKeyPair: IdentityKeyPair,
  keyId: number,
): Promise<SignedPreKey> {
  const s = await ensureSodium();
  const keyPair = s.crypto_box_keypair();
  const signature = s.crypto_sign_detached(keyPair.publicKey, identityKeyPair.privateKey);
  return {
    keyId,
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    signature,
    timestamp: Date.now(),
  };
}

/**
 * Generate a batch of one-time pre-keys (X25519).
 *
 * One-time pre-keys provide forward secrecy for the initial key exchange.
 * Each key is used exactly once and then discarded.
 *
 * @param count - Number of one-time pre-keys to generate
 * @param startId - Starting key ID (sequential IDs are assigned)
 */
export async function generateOneTimePreKeys(
  count: number,
  startId: number = 0,
): Promise<OneTimePreKey[]> {
  const s = await ensureSodium();
  const keys: OneTimePreKey[] = [];
  for (let i = 0; i < count; i++) {
    const keyPair = s.crypto_box_keypair();
    keys.push({
      keyId: startId + i,
      publicKey: keyPair.publicKey,
      privateKey: keyPair.privateKey,
    });
  }
  return keys;
}
