/**
 * Murmuring Protocol Types
 *
 * Core type definitions for the Murmuring federated communication protocol.
 */

/** Semantic version string for protocol versioning */
export interface ProtocolVersion {
  major: number;
  minor: number;
  patch: number;
}

/** Privacy manifest published at /.well-known/privacy-manifest */
export interface PrivacyManifest {
  protocol: string;
  version: string;
  node: {
    name: string;
    domain: string;
  };
  data_collected: string[];
  data_not_collected: string[];
  encryption: {
    e2ee_default: boolean;
    algorithm: string;
    mls_support: boolean;
  };
  retention: {
    message_max_days: number | null;
    media_max_days: number | null;
    metadata_max_days: number | null;
  };
  federation: {
    enabled: boolean;
    allow_list: string[] | null;
    deny_list: string[];
  };
}

/** Hybrid Logical Clock timestamp for causal ordering */
export interface HLCTimestamp {
  /** Wall clock time in milliseconds since Unix epoch */
  wallTime: number;
  /** Logical counter for events at the same wall time */
  logical: number;
  /** Node ID that generated this timestamp */
  nodeId: string;
}

/** Wire format for messages between nodes */
export interface MessageEnvelope {
  /** Unique message ID (UUID v7) */
  id: string;
  /** ActivityPub actor URI of the author */
  author: string;
  /** Channel identifier */
  channelId: string;
  /** Plaintext content (unencrypted channels) */
  content?: string;
  /** Encrypted content (E2EE channels) */
  ciphertext?: string;
  /** HLC timestamp for causal ordering */
  hlc: HLCTimestamp;
  /** Ed25519 signature over the canonical envelope */
  signature: string;
  /** Protocol version */
  version: string;
  /** Optional: ID of the message being replied to */
  replyTo?: string;
  /** Optional: edit revision number (0 = original) */
  editRevision?: number;
}

/** Health check response from any Murmuring service */
export interface HealthCheckResponse {
  status: "healthy" | "degraded" | "unhealthy";
  version: string;
  services: {
    [name: string]: {
      status: "up" | "down";
      latencyMs?: number;
    };
  };
}

/** Federation handshake metadata at /.well-known/murmuring-federation */
export interface FederationMetadata {
  protocol: string;
  version: string;
  nodeName: string;
  domain: string;
  inbox: string;
  outbox: string;
  publicKey: {
    id: string;
    type: string;
    publicKeyPem: string;
  };
  capabilities: string[];
}

/** Supported ActivityPub extension types */
export type MurmuringActivityType =
  | "MurmuringServer"
  | "MurmuringChannel"
  | "MurmuringMessage"
  | "MurmuringRole"
  | "MurmuringReaction";
