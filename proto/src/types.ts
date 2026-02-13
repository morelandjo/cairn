/**
 * Cairn Protocol Types
 *
 * Core type definitions for the Cairn federated communication protocol.
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

/** Health check response from any Cairn service */
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

/** Federation handshake metadata at /.well-known/cairn-federation */
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
export type CairnActivityType =
  | "CairnServer"
  | "CairnChannel"
  | "CairnMessage"
  | "CairnRole"
  | "CairnReaction";

// ─── Server/Guild Types ───

/** A CairnServer (guild) that owns channels, roles, and members */
export interface Server {
  id: string;
  name: string;
  description?: string;
  icon_key?: string;
  creator_id: string;
  inserted_at: string;
}

/** Server membership record */
export interface ServerMember {
  id: string;
  username: string;
  display_name?: string;
  role_id?: string;
  role_name?: string;
}

/** Server role with permissions */
export interface ServerRole {
  id: string;
  name: string;
  permissions: Record<string, boolean>;
  priority: number;
  color?: string;
}

/** Protocol-defined permission keys */
export type PermissionKey =
  | "send_messages"
  | "read_messages"
  | "manage_messages"
  | "manage_channels"
  | "manage_roles"
  | "manage_server"
  | "kick_members"
  | "ban_members"
  | "invite_members"
  | "manage_webhooks"
  | "attach_files"
  | "use_voice"
  | "mute_members"
  | "deafen_members"
  | "move_members";

// ─── Federation Node Types ───

/** A remote federated node */
export interface FederatedNode {
  id: string;
  domain: string;
  node_id: string;
  status: "pending" | "active" | "blocked";
  protocol_version: string;
  inserted_at: string;
}

/** A federation activity log entry */
export interface FederationActivity {
  id: string;
  activity_type: string;
  direction: "inbound" | "outbound";
  actor_uri?: string;
  object_uri?: string;
  status: "pending" | "delivered" | "failed";
  error?: string;
  node_domain: string;
  inserted_at: string;
}

// ─── Phase 4: Moderation & Community Types ───

/** Emoji reaction on a message */
export interface Reaction {
  emoji: string;
  count: number;
  me: boolean;
}

/** Channel category for organizing channels */
export interface ChannelCategory {
  id: string;
  name: string;
  position: number;
  server_id: string;
}

/** Pinned message reference */
export interface PinnedMessage {
  id: string;
  message_id: string;
  channel_id: string;
  pinned_by_id: string;
  inserted_at: string;
}

/** Custom emoji uploaded to a server */
export interface CustomEmoji {
  id: string;
  name: string;
  file_key: string;
  server_id: string;
  animated: boolean;
  inserted_at: string;
}

/** Webhook for external integrations */
export interface Webhook {
  id: string;
  name: string;
  token?: string;
  channel_id: string;
  server_id: string;
  avatar_key?: string;
}

/** Bot account */
export interface BotAccount {
  id: string;
  user_id: string;
  username: string;
  server_id: string;
  allowed_channels: string[];
  token?: string;
}

/** Notification preference */
export interface NotificationPreference {
  id: string;
  user_id: string;
  server_id?: string;
  channel_id?: string;
  level: "all" | "mentions" | "nothing";
  dnd_enabled: boolean;
  quiet_hours_start?: string;
  quiet_hours_end?: string;
}

/** Server directory entry for public discovery */
export interface DirectoryEntry {
  id: string;
  server_id: string;
  server_name: string;
  description?: string;
  tags: string[];
  member_count: number;
  listed_at: string;
}

/** Moderation log entry */
export interface ModLogEntry {
  id: string;
  server_id: string;
  moderator_id: string;
  target_user_id: string;
  action: string;
  details?: Record<string, unknown>;
  inserted_at: string;
}

/** Message report */
export interface MessageReport {
  id: string;
  message_id: string;
  reporter_id: string;
  server_id: string;
  reason: string;
  details?: string;
  status: "pending" | "dismissed" | "actioned";
  resolved_by_id?: string;
  resolution_action?: string;
  inserted_at: string;
}

/** Auto-moderation rule */
export interface AutoModRule {
  id: string;
  server_id: string;
  rule_type: "word_filter" | "regex_filter" | "link_filter" | "mention_spam";
  enabled: boolean;
  config: Record<string, unknown>;
}

/** Link preview metadata */
export interface LinkPreview {
  url: string;
  title?: string;
  description?: string;
  image_url?: string;
  site_name?: string;
}

// ─── Voice/Video Types ───

/** Voice state for a user in a voice channel */
export interface VoiceState {
  userId: string;
  channelId: string;
  muted: boolean;
  deafened: boolean;
  videoOn: boolean;
  screenSharing: boolean;
  speaking: boolean;
}

/** WebRTC transport parameters from SFU */
export interface VoiceTransportParams {
  id: string;
  iceParameters: Record<string, unknown>;
  iceCandidates: Record<string, unknown>[];
  dtlsParameters: Record<string, unknown>;
}

/** ICE/TURN server configuration */
export interface IceServerConfig {
  urls: string[];
  username?: string;
  credential?: string;
}

// ─── Federated User Types ───

/** A cached remote (federated) user profile */
export interface FederatedUser {
  id: string;
  did: string;
  username: string;
  display_name?: string;
  home_instance: string;
  public_key: string;
  avatar_url?: string;
  actor_uri: string;
  last_synced_at: string;
}

// ─── DID Identity Types ───

/** A DID operation in the hash-chained operation log */
export interface DIDOperation {
  seq: number;
  operation_type:
    | "create"
    | "rotate_signing_key"
    | "rotate_rotation_key"
    | "update_handle"
    | "deactivate";
  payload: Record<string, unknown>;
  signature: string;
  prev_hash: string | null;
  inserted_at: string;
}

/** DID document as resolved from the operation chain */
export interface DIDDocument {
  "@context": string[];
  id: string;
  verificationMethod: Array<{
    id: string;
    type: string;
    controller: string;
    publicKeyMultibase: string;
  }>;
  authentication: string[];
  service: Array<{
    id: string;
    type: string;
    serviceEndpoint: string;
  }>;
  alsoKnownAs?: string[];
}

// ─── Cross-Instance DM Types ───

/** A DM request from a local user to a remote DID */
export interface DmRequest {
  id: string;
  channel_id: string;
  sender_id?: string;
  sender_username?: string;
  sender_display_name?: string;
  recipient_did: string;
  recipient_instance: string;
  status: "pending" | "accepted" | "rejected" | "blocked";
  inserted_at: string;
}

/** A DM channel with a federated participant */
export interface FederatedDmChannel {
  id: string;
  channel_id: string;
  recipient_did: string;
  recipient_instance: string;
  status: "pending" | "accepted" | "rejected" | "blocked";
}

/** Key bundle fetched from a remote instance for cross-instance X3DH */
export interface FederatedKeyBundle {
  did: string;
  identity_public_key: string;
  signed_prekey: string;
  signed_prekey_signature: string;
  one_time_prekey?: {
    key_id: number;
    public_key: string;
  };
}

// ─── E2EE Crypto Types ───

/** Generic key pair with public and private keys */
export interface KeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

/** Ed25519 identity key pair for long-term signing */
export interface IdentityKeyPair {
  /** Ed25519 public key (32 bytes) */
  publicKey: Uint8Array;
  /** Ed25519 private key (64 bytes) */
  privateKey: Uint8Array;
  /** Key type discriminator */
  keyType: "ed25519";
}

/** X25519 signed pre-key for key agreement, signed with identity key */
export interface SignedPreKey {
  /** Unique key ID */
  keyId: number;
  /** X25519 public key (32 bytes) */
  publicKey: Uint8Array;
  /** X25519 private key (32 bytes) */
  privateKey: Uint8Array;
  /** Ed25519 signature over the public key */
  signature: Uint8Array;
  /** Timestamp of key generation (ms since epoch) */
  timestamp: number;
}

/** X25519 one-time pre-key for single-use key agreement */
export interface OneTimePreKey {
  /** Unique key ID */
  keyId: number;
  /** X25519 public key (32 bytes) */
  publicKey: Uint8Array;
  /** X25519 private key (32 bytes) */
  privateKey: Uint8Array;
}

/** Public key bundle advertised by a user for X3DH key exchange */
export interface KeyBundle {
  /** Ed25519 identity public key */
  identityKey: Uint8Array;
  /** X25519 signed pre-key public key */
  signedPreKey: Uint8Array;
  /** Ed25519 signature of the signed pre-key */
  signedPreKeySignature: Uint8Array;
  /** Signed pre-key ID */
  signedPreKeyId: number;
  /** Optional X25519 one-time pre-key public key */
  oneTimePreKey?: Uint8Array;
  /** Optional one-time pre-key ID */
  oneTimePreKeyId?: number;
}

/** Header for a Double Ratchet message */
export interface RatchetHeader {
  /** Sender's current DH ratchet public key (X25519, 32 bytes) */
  dhPublicKey: Uint8Array;
  /** Number of messages in the previous sending chain */
  previousChainLength: number;
  /** Message number in the current sending chain */
  messageNumber: number;
}

/** Encrypted payload in the Cairn wire format */
export interface EncryptedPayload {
  /** Ratchet header */
  header: RatchetHeader;
  /** Encrypted ciphertext bytes */
  ciphertext: Uint8Array;
  /** Nonce used for encryption (24 bytes for XChaCha20-Poly1305) */
  nonce: Uint8Array;
}

/** Serializable ratchet state for persistence */
export interface RatchetState {
  /** Our current DH ratchet key pair */
  dhKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array };
  /** Peer's current DH ratchet public key */
  peerDhPublicKey: Uint8Array;
  /** Root key (32 bytes) */
  rootKey: Uint8Array;
  /** Sending chain key (32 bytes), null if not yet initialized */
  sendingChainKey: Uint8Array | null;
  /** Receiving chain key (32 bytes), null if not yet initialized */
  receivingChainKey: Uint8Array | null;
  /** Number of messages sent in the current sending chain */
  sendMessageNumber: number;
  /** Number of messages received in the current receiving chain */
  receiveMessageNumber: number;
  /** Number of messages in the previous sending chain */
  previousChainLength: number;
  /** Skipped message keys indexed by "dhPublicKey:messageNumber" */
  skippedKeys: Record<string, Uint8Array>;
}
