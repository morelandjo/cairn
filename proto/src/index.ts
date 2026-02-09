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
