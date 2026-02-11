/**
 * Murmuring E2EE crypto module.
 *
 * Provides key generation, X3DH key exchange, Double Ratchet message
 * encryption, and IndexedDB-based key persistence.
 */

export {
  ensureSodium,
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
} from "./keys.js";

export {
  x3dhInitiate,
  x3dhRespond,
  type X3DHInitResult,
} from "./x3dh.js";

export { DoubleRatchet } from "./ratchet.js";

export { encryptMessage, decryptMessage } from "./encrypt.js";

export { KeyStore } from "./key-store.js";

export {
  deriveVoiceKey,
  encryptFrame,
  decryptFrame,
  supportsInsertableStreams,
  createEncryptTransform,
  createDecryptTransform,
} from "./voiceEncryption.js";

export {
  base58Encode,
  base58Decode,
  multibaseEncode,
  multibaseDecode,
  canonicalJson,
  createGenesisOperation,
  signOperation,
  hashOperation,
  computeDid,
  verifyOperationChain,
  replayOperations,
} from "./did.js";

export type { GenesisResult } from "./did.js";
