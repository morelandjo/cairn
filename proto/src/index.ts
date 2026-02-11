/**
 * @murmuring/proto — Murmuring Protocol definitions
 *
 * Shared types, constants, and protocol definitions for the
 * Murmuring federated communication platform.
 */

export type {
  ProtocolVersion,
  PrivacyManifest,
  HLCTimestamp,
  MessageEnvelope,
  HealthCheckResponse,
  FederationMetadata,
  MurmuringActivityType,
  KeyPair,
  IdentityKeyPair,
  SignedPreKey,
  OneTimePreKey,
  KeyBundle,
  RatchetHeader,
  EncryptedPayload,
  RatchetState,
  VoiceState,
  VoiceTransportParams,
  IceServerConfig,
  DIDOperation,
  DIDDocument,
  FederatedUser,
  DmRequest,
  FederatedKeyBundle,
} from "./types.js";

export {
  PROTOCOL_VERSION,
  PROTOCOL_VERSION_STRING,
  PROTOCOL_NAME,
  MURMURING_NS,
  WELL_KNOWN,
  ALLOWED_MARKDOWN,
  LIMITS,
  CIPHERSUITES,
} from "./constants.js";

export {
  ensureSodium,
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
  x3dhInitiate,
  x3dhRespond,
  DoubleRatchet,
  encryptMessage,
  decryptMessage,
  KeyStore,
} from "./crypto/index.js";

export type { X3DHInitResult } from "./crypto/index.js";

export {
  deriveVoiceKey,
  encryptFrame,
  decryptFrame,
  supportsInsertableStreams,
  createEncryptTransform,
  createDecryptTransform,
} from "./crypto/index.js";

export { MlsClient, exportKeys, importKeys } from "./mls/index.js";

export type {
  MlsCredential,
  MlsKeyPackage,
  MlsAddMemberResult,
  MlsProcessedMessage,
  MlsGroupMember,
  KeyBackupPayload,
} from "./mls/index.js";

// API client
export { ApiClient, apiClient } from "./api/index.js";
export type { ApiClientOptions, ApiTransport, ApiResponse } from "./api/index.js";
export { FetchTransport } from "./api/index.js";
export {
  authApi,
  channelsApi,
  serversApi,
  moderationApi,
  uploadApi,
  searchApi,
  invitesApi,
  notificationsApi,
  discoveryApi,
  webhooksApi,
  mlsApi,
  voiceApi,
  pushTokensApi,
  identityApi,
  federationApi,
  dmApi,
} from "./api/index.js";
