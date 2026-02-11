/**
 * Type declarations for libsodium-wrappers.
 *
 * Minimal declarations covering the APIs used by the Murmuring crypto module.
 * The official package does not ship .d.ts files.
 */
declare module "libsodium-wrappers-sumo" {
  /** Promise that resolves when libsodium is initialized */
  const ready: Promise<void>;

  // ─── Constants ───

  const crypto_sign_PUBLICKEYBYTES: number;
  const crypto_sign_SECRETKEYBYTES: number;
  const crypto_sign_BYTES: number;
  const crypto_box_PUBLICKEYBYTES: number;
  const crypto_box_SECRETKEYBYTES: number;
  const crypto_aead_xchacha20poly1305_ietf_KEYBYTES: number;
  const crypto_aead_xchacha20poly1305_ietf_NPUBBYTES: number;
  const crypto_aead_xchacha20poly1305_ietf_ABYTES: number;
  const crypto_pwhash_OPSLIMIT_INTERACTIVE: number;
  const crypto_pwhash_MEMLIMIT_INTERACTIVE: number;
  const crypto_pwhash_ALG_ARGON2ID13: number;
  const crypto_scalarmult_BYTES: number;
  const crypto_scalarmult_SCALARBYTES: number;

  // ─── Key Pair Types ───

  interface KeyPair {
    publicKey: Uint8Array;
    privateKey: Uint8Array;
    keyType: string;
  }

  // ─── Signing (Ed25519) ───

  function crypto_sign_keypair(): KeyPair;
  function crypto_sign_detached(message: Uint8Array, privateKey: Uint8Array): Uint8Array;
  function crypto_sign_verify_detached(
    signature: Uint8Array,
    message: Uint8Array,
    publicKey: Uint8Array,
  ): boolean;

  // ─── Ed25519 <-> X25519 Conversion ───

  function crypto_sign_ed25519_pk_to_curve25519(ed25519Pk: Uint8Array): Uint8Array;
  function crypto_sign_ed25519_sk_to_curve25519(ed25519Sk: Uint8Array): Uint8Array;

  // ─── Public-Key Encryption (X25519 / Curve25519) ───

  function crypto_box_keypair(): KeyPair;
  function crypto_scalarmult(privateKey: Uint8Array, publicKey: Uint8Array): Uint8Array;

  // ─── AEAD (XChaCha20-Poly1305) ───

  function crypto_aead_xchacha20poly1305_ietf_encrypt(
    message: Uint8Array,
    additionalData: Uint8Array | null,
    secretNonce: Uint8Array | null,
    publicNonce: Uint8Array,
    key: Uint8Array,
  ): Uint8Array;

  function crypto_aead_xchacha20poly1305_ietf_decrypt(
    secretNonce: Uint8Array | null,
    ciphertext: Uint8Array,
    additionalData: Uint8Array | null,
    publicNonce: Uint8Array,
    key: Uint8Array,
  ): Uint8Array;

  // ─── HMAC-SHA-256 ───

  function crypto_auth_hmacsha256(message: Uint8Array, key: Uint8Array): Uint8Array;

  // ─── Password Hashing (Argon2id) ───

  function crypto_pwhash(
    keyLength: number,
    password: string | Uint8Array,
    salt: Uint8Array,
    opsLimit: number,
    memLimit: number,
    algorithm: number,
  ): Uint8Array;

  // ─── Random ───

  function randombytes_buf(length: number): Uint8Array;

  // ─── Encoding ───

  function to_hex(input: Uint8Array): string;
  function from_hex(input: string): Uint8Array;
  function to_base64(input: Uint8Array, variant?: number): string;
  function from_base64(input: string, variant?: number): Uint8Array;
  function from_string(input: string): Uint8Array;
  function to_string(input: Uint8Array): string;

  // ─── Default Export ───

  const _default: {
    ready: typeof ready;
    crypto_sign_PUBLICKEYBYTES: typeof crypto_sign_PUBLICKEYBYTES;
    crypto_sign_SECRETKEYBYTES: typeof crypto_sign_SECRETKEYBYTES;
    crypto_sign_BYTES: typeof crypto_sign_BYTES;
    crypto_box_PUBLICKEYBYTES: typeof crypto_box_PUBLICKEYBYTES;
    crypto_box_SECRETKEYBYTES: typeof crypto_box_SECRETKEYBYTES;
    crypto_aead_xchacha20poly1305_ietf_KEYBYTES: typeof crypto_aead_xchacha20poly1305_ietf_KEYBYTES;
    crypto_aead_xchacha20poly1305_ietf_NPUBBYTES: typeof crypto_aead_xchacha20poly1305_ietf_NPUBBYTES;
    crypto_aead_xchacha20poly1305_ietf_ABYTES: typeof crypto_aead_xchacha20poly1305_ietf_ABYTES;
    crypto_pwhash_OPSLIMIT_INTERACTIVE: typeof crypto_pwhash_OPSLIMIT_INTERACTIVE;
    crypto_pwhash_MEMLIMIT_INTERACTIVE: typeof crypto_pwhash_MEMLIMIT_INTERACTIVE;
    crypto_pwhash_ALG_ARGON2ID13: typeof crypto_pwhash_ALG_ARGON2ID13;
    crypto_scalarmult_BYTES: typeof crypto_scalarmult_BYTES;
    crypto_scalarmult_SCALARBYTES: typeof crypto_scalarmult_SCALARBYTES;
    crypto_sign_keypair: typeof crypto_sign_keypair;
    crypto_sign_detached: typeof crypto_sign_detached;
    crypto_sign_verify_detached: typeof crypto_sign_verify_detached;
    crypto_sign_ed25519_pk_to_curve25519: typeof crypto_sign_ed25519_pk_to_curve25519;
    crypto_sign_ed25519_sk_to_curve25519: typeof crypto_sign_ed25519_sk_to_curve25519;
    crypto_box_keypair: typeof crypto_box_keypair;
    crypto_scalarmult: typeof crypto_scalarmult;
    crypto_aead_xchacha20poly1305_ietf_encrypt: typeof crypto_aead_xchacha20poly1305_ietf_encrypt;
    crypto_aead_xchacha20poly1305_ietf_decrypt: typeof crypto_aead_xchacha20poly1305_ietf_decrypt;
    crypto_auth_hmacsha256: typeof crypto_auth_hmacsha256;
    crypto_pwhash: typeof crypto_pwhash;
    randombytes_buf: typeof randombytes_buf;
    to_hex: typeof to_hex;
    from_hex: typeof from_hex;
    to_base64: typeof to_base64;
    from_base64: typeof from_base64;
    from_string: typeof from_string;
    to_string: typeof to_string;
  };

  export default _default;
}
