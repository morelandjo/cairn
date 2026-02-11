/**
 * IndexedDB-based key persistence for the Murmuring E2EE protocol.
 *
 * Stores identity keys (encrypted with a passphrase via Argon2id + XChaCha20-Poly1305)
 * and ratchet sessions in the browser's IndexedDB.
 *
 * This module is browser-only. In Node.js test environments, IndexedDB must be mocked.
 */

import { ensureSodium } from "./keys.js";
import type { IdentityKeyPair, RatchetState } from "../types.js";

/** IndexedDB database name */
const DB_NAME = "murmuring-keystore";

/** IndexedDB database version */
const DB_VERSION = 1;

/** Object store names */
const STORE_IDENTITY = "identity";
const STORE_SESSIONS = "sessions";

/** Salt length for Argon2id key derivation */
const ARGON2_SALT_LENGTH = 16;

/**
 * Minimal IndexedDB wrapper providing promise-based access.
 */
function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_IDENTITY)) {
        db.createObjectStore(STORE_IDENTITY);
      }
      if (!db.objectStoreNames.contains(STORE_SESSIONS)) {
        db.createObjectStore(STORE_SESSIONS);
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/**
 * Put a value into an IndexedDB object store.
 */
function idbPut(db: IDBDatabase, storeName: string, key: string, value: unknown): Promise<void> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readwrite");
    const store = tx.objectStore(storeName);
    const request = store.put(value, key);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

/**
 * Get a value from an IndexedDB object store.
 */
function idbGet<T>(db: IDBDatabase, storeName: string, key: string): Promise<T | undefined> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readonly");
    const store = tx.objectStore(storeName);
    const request = store.get(key);
    request.onsuccess = () => resolve(request.result as T | undefined);
    request.onerror = () => reject(request.error);
  });
}

/**
 * Delete a value from an IndexedDB object store.
 */
function idbDelete(db: IDBDatabase, storeName: string, key: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readwrite");
    const store = tx.objectStore(storeName);
    const request = store.delete(key);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

/** Stored format for an encrypted identity key */
interface StoredIdentityKey {
  /** Argon2id salt */
  salt: Uint8Array;
  /** XChaCha20-Poly1305 nonce */
  nonce: Uint8Array;
  /** Encrypted private key */
  encryptedPrivateKey: Uint8Array;
  /** Public key (not encrypted) */
  publicKey: Uint8Array;
}

/** Stored format for a serialized ratchet session */
interface StoredSession {
  state: RatchetState;
}

/**
 * Key store for persisting E2EE key material in IndexedDB.
 *
 * Identity key private material is encrypted at rest using a passphrase
 * derived key (Argon2id + XChaCha20-Poly1305). Ratchet sessions are stored
 * as-is (they contain only ephemeral key material).
 */
export class KeyStore {
  private db: IDBDatabase | null = null;

  /**
   * Open the IndexedDB database. Must be called before other operations.
   */
  async open(): Promise<void> {
    this.db = await openDatabase();
  }

  /**
   * Close the IndexedDB database.
   */
  close(): void {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }

  private getDb(): IDBDatabase {
    if (!this.db) {
      throw new Error("KeyStore: Database not opened. Call open() first.");
    }
    return this.db;
  }

  /**
   * Store an identity key pair, encrypting the private key with a passphrase.
   *
   * Uses Argon2id for key derivation and XChaCha20-Poly1305 for encryption.
   *
   * @param keyPair - The Ed25519 identity key pair to store
   * @param passphrase - The passphrase to encrypt the private key with
   */
  async storeIdentityKeyPair(keyPair: IdentityKeyPair, passphrase: string): Promise<void> {
    const s = await ensureSodium();
    const db = this.getDb();

    // Generate salt for Argon2id
    const salt = s.randombytes_buf(ARGON2_SALT_LENGTH);

    // Derive encryption key from passphrase using Argon2id
    const key = s.crypto_pwhash(
      s.crypto_aead_xchacha20poly1305_ietf_KEYBYTES,
      passphrase,
      salt,
      s.crypto_pwhash_OPSLIMIT_INTERACTIVE,
      s.crypto_pwhash_MEMLIMIT_INTERACTIVE,
      s.crypto_pwhash_ALG_ARGON2ID13,
    );

    // Encrypt the private key
    const nonce = s.randombytes_buf(s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES);
    const encryptedPrivateKey = s.crypto_aead_xchacha20poly1305_ietf_encrypt(
      keyPair.privateKey,
      null,
      null,
      nonce,
      key,
    );

    const stored: StoredIdentityKey = {
      salt,
      nonce,
      encryptedPrivateKey,
      publicKey: keyPair.publicKey,
    };

    await idbPut(db, STORE_IDENTITY, "current", stored);
  }

  /**
   * Load and decrypt the identity key pair.
   *
   * @param passphrase - The passphrase to decrypt the private key with
   * @returns The decrypted identity key pair, or null if not found
   */
  async loadIdentityKeyPair(passphrase: string): Promise<IdentityKeyPair | null> {
    const s = await ensureSodium();
    const db = this.getDb();

    const stored = await idbGet<StoredIdentityKey>(db, STORE_IDENTITY, "current");
    if (!stored) return null;

    // Derive the decryption key from the passphrase
    const key = s.crypto_pwhash(
      s.crypto_aead_xchacha20poly1305_ietf_KEYBYTES,
      passphrase,
      stored.salt,
      s.crypto_pwhash_OPSLIMIT_INTERACTIVE,
      s.crypto_pwhash_MEMLIMIT_INTERACTIVE,
      s.crypto_pwhash_ALG_ARGON2ID13,
    );

    // Decrypt the private key
    const privateKey = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
      null,
      stored.encryptedPrivateKey,
      null,
      stored.nonce,
      key,
    );

    return {
      publicKey: stored.publicKey,
      privateKey,
      keyType: "ed25519",
    };
  }

  /**
   * Store a serialized ratchet session for a peer.
   *
   * @param peerId - The peer's unique identifier
   * @param ratchetState - The serialized ratchet state
   */
  async storeRatchetSession(peerId: string, ratchetState: RatchetState): Promise<void> {
    const db = this.getDb();
    const stored: StoredSession = { state: ratchetState };
    await idbPut(db, STORE_SESSIONS, peerId, stored);
  }

  /**
   * Load a ratchet session for a peer.
   *
   * @param peerId - The peer's unique identifier
   * @returns The ratchet state, or null if no session exists
   */
  async loadRatchetSession(peerId: string): Promise<RatchetState | null> {
    const db = this.getDb();
    const stored = await idbGet<StoredSession>(db, STORE_SESSIONS, peerId);
    return stored?.state ?? null;
  }

  /**
   * Delete a ratchet session for a peer.
   *
   * @param peerId - The peer's unique identifier
   */
  async deleteRatchetSession(peerId: string): Promise<void> {
    const db = this.getDb();
    await idbDelete(db, STORE_SESSIONS, peerId);
  }
}
