/**
 * MLS credential bundle — identity + signing key pair.
 */
export interface MlsCredential {
  /** The identity bytes (Ed25519 public key, 32 bytes). */
  identity: Uint8Array;
  /** The MLS signing public key (Ed25519, 32 bytes). */
  signingPublicKey: Uint8Array;
  /** The MLS signing private key (Ed25519 seed, 32 bytes). */
  signingPrivateKey: Uint8Array;
}

/**
 * A generated MLS KeyPackage with its private state.
 */
export interface MlsKeyPackage {
  /** TLS-serialized public KeyPackage (upload to server). */
  keyPackageData: Uint8Array;
  /** HPKE init private key (keep locally for Welcome processing). */
  initPrivateKey: Uint8Array;
}

/**
 * Result of adding a member to an MLS group.
 */
export interface MlsAddMemberResult {
  /** TLS-serialized Commit message (broadcast to existing group members). */
  commit: Uint8Array;
  /** TLS-serialized Welcome message (send to the new member). */
  welcome: Uint8Array;
}

/**
 * Result of processing an incoming MLS group message.
 */
export interface MlsProcessedMessage {
  /** Message type: "application" | "commit" | "proposal" | "external_proposal". */
  messageType: string;
  /** Decrypted plaintext (only for "application" messages, empty otherwise). */
  plaintext: Uint8Array;
  /** Identity of the sender (BasicCredential identity bytes). */
  senderIdentity: Uint8Array;
}

/**
 * A member in an MLS group.
 */
export interface MlsGroupMember {
  /** Leaf node index in the ratchet tree. */
  index: number;
  /** Identity bytes from the member's credential. */
  identity: Uint8Array;
  /** The member's signature public key. */
  signatureKey: Uint8Array;
}
