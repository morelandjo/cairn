/**
 * Double Ratchet protocol implementation.
 *
 * The Double Ratchet combines a Diffie-Hellman ratchet with a symmetric-key
 * ratchet to provide forward secrecy and break-in recovery for encrypted
 * messages.
 *
 * Based on the Signal Double Ratchet specification:
 * https://signal.org/docs/specifications/doubleratchet/
 *
 * Key derivation:
 * - DH ratchet: X25519 key exchange to derive new root and chain keys
 * - Symmetric ratchet: HMAC-SHA-256 chain to derive message keys
 * - Message encryption: XChaCha20-Poly1305
 */

import sodium from "libsodium-wrappers-sumo";
import { ensureSodium } from "./keys.js";
import { hkdf } from "./x3dh.js";
import type { RatchetHeader, RatchetState } from "../types.js";

/** Maximum number of skipped message keys to store */
const MAX_SKIP = 1000;

/** Info string for root key KDF */
const ROOT_KDF_INFO = "murmuring-ratchet-root-v1";

/** Byte used for chain key derivation (message key) */
const CHAIN_KEY_MSG = 0x01;

/** Byte used for chain key derivation (next chain key) */
const CHAIN_KEY_CHAIN = 0x02;

/**
 * Derive a new root key and chain key from the current root key and a DH output.
 */
async function kdfRootKey(
  rootKey: Uint8Array,
  dhOutput: Uint8Array,
): Promise<{ rootKey: Uint8Array; chainKey: Uint8Array }> {
  const derived = await hkdf(rootKey, dhOutput, ROOT_KDF_INFO, 64);
  return {
    rootKey: derived.slice(0, 32),
    chainKey: derived.slice(32, 64),
  };
}

/**
 * Derive a message key and next chain key from the current chain key.
 *
 * Uses HMAC-SHA-256 as a KDF chain:
 * - Message key = HMAC(chainKey, 0x01)
 * - Next chain key = HMAC(chainKey, 0x02)
 */
async function kdfChainKey(
  chainKey: Uint8Array,
): Promise<{ messageKey: Uint8Array; nextChainKey: Uint8Array }> {
  const s = await ensureSodium();
  const messageKey = s.crypto_auth_hmacsha256(new Uint8Array([CHAIN_KEY_MSG]), chainKey);
  const nextChainKey = s.crypto_auth_hmacsha256(new Uint8Array([CHAIN_KEY_CHAIN]), chainKey);
  return { messageKey, nextChainKey };
}

/**
 * Perform an X25519 DH exchange.
 */
async function dh(privateKey: Uint8Array, publicKey: Uint8Array): Promise<Uint8Array> {
  const s = await ensureSodium();
  return s.crypto_scalarmult(privateKey, publicKey);
}

/**
 * Generate a new X25519 key pair for the DH ratchet.
 */
async function generateDhKeyPair(): Promise<{ publicKey: Uint8Array; privateKey: Uint8Array }> {
  const s = await ensureSodium();
  const kp = s.crypto_box_keypair();
  return { publicKey: kp.publicKey, privateKey: kp.privateKey };
}

/**
 * Create a string key for the skipped messages map.
 */
function skippedKeyId(dhPublicKey: Uint8Array, messageNumber: number): string {
  const s = sodium;
  return `${s.to_hex(dhPublicKey)}:${messageNumber}`;
}

/**
 * Double Ratchet session for encrypted communication.
 *
 * After X3DH establishes a shared secret, Alice and Bob each create a
 * DoubleRatchet instance to encrypt and decrypt messages. The ratchet
 * automatically rotates keys with each message exchange.
 */
export class DoubleRatchet {
  private dhKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array };
  private peerDhPublicKey: Uint8Array;
  private rootKey: Uint8Array;
  private sendingChainKey: Uint8Array | null;
  private receivingChainKey: Uint8Array | null;
  private sendMessageNumber: number;
  private receiveMessageNumber: number;
  private previousChainLength: number;
  private skippedKeys: Map<string, Uint8Array>;

  private constructor(
    dhKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array },
    peerDhPublicKey: Uint8Array,
    rootKey: Uint8Array,
    sendingChainKey: Uint8Array | null,
    receivingChainKey: Uint8Array | null,
    sendMessageNumber: number,
    receiveMessageNumber: number,
    previousChainLength: number,
    skippedKeys: Map<string, Uint8Array>,
  ) {
    this.dhKeyPair = dhKeyPair;
    this.peerDhPublicKey = peerDhPublicKey;
    this.rootKey = rootKey;
    this.sendingChainKey = sendingChainKey;
    this.receivingChainKey = receivingChainKey;
    this.sendMessageNumber = sendMessageNumber;
    this.receiveMessageNumber = receiveMessageNumber;
    this.previousChainLength = previousChainLength;
    this.skippedKeys = skippedKeys;
  }

  /**
   * Initialize the ratchet as Alice (the initiator).
   *
   * Alice performs the first DH ratchet step immediately since she knows
   * Bob's signed pre-key (used as his initial DH ratchet key).
   *
   * @param sharedSecret - The X3DH shared secret (used as initial root key)
   * @param peerPublicKey - Bob's signed pre-key public key (X25519)
   */
  static async initAsAlice(
    sharedSecret: Uint8Array,
    peerPublicKey: Uint8Array,
  ): Promise<DoubleRatchet> {
    const dhKeyPair = await generateDhKeyPair();
    const dhOutput = await dh(dhKeyPair.privateKey, peerPublicKey);
    const { rootKey, chainKey } = await kdfRootKey(sharedSecret, dhOutput);

    return new DoubleRatchet(
      dhKeyPair,
      peerPublicKey,
      rootKey,
      chainKey,       // sending chain key
      null,           // no receiving chain key yet
      0,              // send message number
      0,              // receive message number
      0,              // previous chain length
      new Map(),      // no skipped keys
    );
  }

  /**
   * Initialize the ratchet as Bob (the responder).
   *
   * Bob uses his signed pre-key pair as his initial DH ratchet key.
   * The first receiving chain will be established when he receives
   * Alice's first message.
   *
   * @param sharedSecret - The X3DH shared secret (used as initial root key)
   * @param keyPair - Bob's signed pre-key pair (X25519)
   */
  static async initAsBob(
    sharedSecret: Uint8Array,
    keyPair: { publicKey: Uint8Array; privateKey: Uint8Array },
  ): Promise<DoubleRatchet> {
    return new DoubleRatchet(
      keyPair,
      new Uint8Array(32), // placeholder, replaced on first received message
      sharedSecret,       // root key = shared secret
      null,               // no sending chain key yet
      null,               // no receiving chain key yet
      0,
      0,
      0,
      new Map(),
    );
  }

  /**
   * Encrypt a plaintext message.
   *
   * Derives a message key from the sending chain, encrypts the plaintext
   * with XChaCha20-Poly1305, and returns the header and ciphertext.
   *
   * @param plaintext - The plaintext bytes to encrypt
   * @returns The ratchet header and encrypted ciphertext
   */
  async encrypt(plaintext: Uint8Array): Promise<{ header: RatchetHeader; ciphertext: Uint8Array; nonce: Uint8Array }> {
    if (!this.sendingChainKey) {
      throw new Error("DoubleRatchet: Sending chain not initialized");
    }

    const s = await ensureSodium();
    const { messageKey, nextChainKey } = await kdfChainKey(this.sendingChainKey);
    this.sendingChainKey = nextChainKey;

    const header: RatchetHeader = {
      dhPublicKey: this.dhKeyPair.publicKey,
      previousChainLength: this.previousChainLength,
      messageNumber: this.sendMessageNumber,
    };
    this.sendMessageNumber++;

    // Encrypt with XChaCha20-Poly1305
    const nonce = s.randombytes_buf(s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES);
    const ciphertext = s.crypto_aead_xchacha20poly1305_ietf_encrypt(
      plaintext,
      null, // no additional data
      null, // secret nonce (unused in ietf variant)
      nonce,
      messageKey,
    );

    return { header, ciphertext, nonce };
  }

  /**
   * Decrypt a received message.
   *
   * Handles DH ratchet rotation if the sender's DH key has changed,
   * skipped messages, and derives the correct message key for decryption.
   *
   * @param header - The ratchet header from the message
   * @param ciphertext - The encrypted ciphertext
   * @param nonce - The nonce used for encryption
   * @returns The decrypted plaintext
   */
  async decrypt(header: RatchetHeader, ciphertext: Uint8Array, nonce: Uint8Array): Promise<Uint8Array> {
    const s = await ensureSodium();

    // Try skipped message keys first
    const skipId = skippedKeyId(header.dhPublicKey, header.messageNumber);
    const skippedKey = this.skippedKeys.get(skipId);
    if (skippedKey) {
      this.skippedKeys.delete(skipId);
      const plaintext = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
        null, // secret nonce (unused)
        ciphertext,
        null, // no additional data
        nonce,
        skippedKey,
      );
      return plaintext;
    }

    // Check if we need to perform a DH ratchet step
    const peerKeyHex = s.to_hex(header.dhPublicKey);
    const currentPeerKeyHex = s.to_hex(this.peerDhPublicKey);

    if (peerKeyHex !== currentPeerKeyHex) {
      // Skip any missed messages in the current receiving chain
      if (this.receivingChainKey !== null) {
        await this.skipMessageKeys(header.previousChainLength - this.receiveMessageNumber);
      }

      // Perform DH ratchet step
      this.previousChainLength = this.sendMessageNumber;
      this.sendMessageNumber = 0;
      this.receiveMessageNumber = 0;
      this.peerDhPublicKey = header.dhPublicKey;

      // New receiving chain
      const dhOutput = await dh(this.dhKeyPair.privateKey, this.peerDhPublicKey);
      const { rootKey: rk1, chainKey: ck1 } = await kdfRootKey(this.rootKey, dhOutput);
      this.rootKey = rk1;
      this.receivingChainKey = ck1;

      // New sending chain with a fresh DH key pair
      this.dhKeyPair = await generateDhKeyPair();
      const dhOutput2 = await dh(this.dhKeyPair.privateKey, this.peerDhPublicKey);
      const { rootKey: rk2, chainKey: ck2 } = await kdfRootKey(this.rootKey, dhOutput2);
      this.rootKey = rk2;
      this.sendingChainKey = ck2;
    }

    // Skip any missed messages in the receiving chain
    await this.skipMessageKeys(header.messageNumber - this.receiveMessageNumber);

    // Derive the message key for this message
    if (!this.receivingChainKey) {
      throw new Error("DoubleRatchet: Receiving chain not initialized");
    }
    const { messageKey, nextChainKey } = await kdfChainKey(this.receivingChainKey);
    this.receivingChainKey = nextChainKey;
    this.receiveMessageNumber++;

    // Decrypt
    const plaintext = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
      null, // secret nonce (unused)
      ciphertext,
      null, // no additional data
      nonce,
      messageKey,
    );

    return plaintext;
  }

  /**
   * Skip ahead in the receiving chain, storing skipped message keys.
   */
  private async skipMessageKeys(count: number): Promise<void> {
    if (count <= 0 || !this.receivingChainKey) return;

    if (this.skippedKeys.size + count > MAX_SKIP) {
      throw new Error("DoubleRatchet: Too many skipped messages");
    }

    for (let i = 0; i < count; i++) {
      const { messageKey, nextChainKey } = await kdfChainKey(this.receivingChainKey);
      const skipId = skippedKeyId(this.peerDhPublicKey, this.receiveMessageNumber);
      this.skippedKeys.set(skipId, messageKey);
      this.receivingChainKey = nextChainKey;
      this.receiveMessageNumber++;
    }
  }

  /**
   * Serialize the ratchet state for persistence.
   *
   * WARNING: The serialized state contains sensitive key material.
   * It must be encrypted before storage.
   */
  serialize(): RatchetState {
    const skippedKeys: Record<string, Uint8Array> = {};
    for (const [key, value] of this.skippedKeys) {
      skippedKeys[key] = new Uint8Array(value);
    }

    return {
      dhKeyPair: {
        publicKey: new Uint8Array(this.dhKeyPair.publicKey),
        privateKey: new Uint8Array(this.dhKeyPair.privateKey),
      },
      peerDhPublicKey: new Uint8Array(this.peerDhPublicKey),
      rootKey: new Uint8Array(this.rootKey),
      sendingChainKey: this.sendingChainKey ? new Uint8Array(this.sendingChainKey) : null,
      receivingChainKey: this.receivingChainKey ? new Uint8Array(this.receivingChainKey) : null,
      sendMessageNumber: this.sendMessageNumber,
      receiveMessageNumber: this.receiveMessageNumber,
      previousChainLength: this.previousChainLength,
      skippedKeys,
    };
  }

  /**
   * Deserialize a persisted ratchet state.
   *
   * @param state - The serialized ratchet state
   */
  static deserialize(state: RatchetState): DoubleRatchet {
    const skippedKeys = new Map<string, Uint8Array>();
    for (const [key, value] of Object.entries(state.skippedKeys)) {
      skippedKeys.set(key, new Uint8Array(value));
    }

    return new DoubleRatchet(
      {
        publicKey: new Uint8Array(state.dhKeyPair.publicKey),
        privateKey: new Uint8Array(state.dhKeyPair.privateKey),
      },
      new Uint8Array(state.peerDhPublicKey),
      new Uint8Array(state.rootKey),
      state.sendingChainKey ? new Uint8Array(state.sendingChainKey) : null,
      state.receivingChainKey ? new Uint8Array(state.receivingChainKey) : null,
      state.sendMessageNumber,
      state.receiveMessageNumber,
      state.previousChainLength,
      skippedKeys,
    );
  }
}
