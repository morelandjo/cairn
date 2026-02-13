/**
 * MLS (Messaging Layer Security) module.
 *
 * Provides MLS group encryption via openmls compiled to WASM.
 * Separate from the X3DH/Double Ratchet crypto module.
 */

export { MlsClient } from "./client.js";
export { EpochTracker } from "./epoch-tracker.js";
export { MessageBuffer } from "./message-buffer.js";

export type {
  MlsCredential,
  MlsKeyPackage,
  MlsAddMemberResult,
  MlsProcessedMessage,
  MlsGroupMember,
} from "./types.js";

export { exportKeys, importKeys } from "./backup.js";

export type { EpochState } from "./epoch-tracker.js";
export type { BufferedMessage, ResyncCallback } from "./message-buffer.js";
export type { KeyBackupPayload } from "./backup.js";
