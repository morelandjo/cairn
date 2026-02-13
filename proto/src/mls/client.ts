/**
 * MLS client — TypeScript wrapper over the WASM MLS implementation.
 *
 * Provides a clean API for MLS credential, KeyPackage, and group operations.
 * WASM must be initialized before use by calling `init()` with the WASM module bytes.
 *
 * Group operations require an active session (call `createSession()` first).
 * Sessions hold cryptographic state (provider, signer) needed for MLS group
 * operations including KeyPackage generation and Welcome processing.
 */
import initWasm, {
  initSync,
  create_credential,
  import_signing_key,
  generate_key_package,
  create_session,
  destroy_session,
  session_generate_key_package,
  create_mls_group,
  add_member,
  remove_member,
  process_welcome,
  encrypt_message,
  process_group_message,
  get_epoch,
  get_members,
  type WasmCredentialBundle,
  type WasmKeyPackageResult,
  type WasmAddMemberResult,
  type WasmProcessedMessage,
} from "../../mls-wasm/pkg/mls_wasm.js";
import type {
  MlsCredential,
  MlsKeyPackage,
  MlsAddMemberResult,
  MlsProcessedMessage,
  MlsGroupMember,
} from "./types.js";

function resultToKeyPackage(result: WasmKeyPackageResult): MlsKeyPackage {
  const kp: MlsKeyPackage = {
    keyPackageData: new Uint8Array(result.keyPackageData),
    initPrivateKey: new Uint8Array(result.initPrivateKey),
  };
  result.free();
  return kp;
}

function bundleToCredential(bundle: WasmCredentialBundle): MlsCredential {
  const credential: MlsCredential = {
    identity: new Uint8Array(bundle.identity),
    signingPublicKey: new Uint8Array(bundle.signingPublicKey),
    signingPrivateKey: new Uint8Array(bundle.signingPrivateKey),
  };
  bundle.free();
  return credential;
}

export class MlsClient {
  private initialized = false;
  private sessionId: number | null = null;

  /**
   * Initialize the WASM module synchronously. Must be called before any other method.
   * @param wasmBytes - The raw WASM module bytes (from fs.readFileSync in Node,
   *   or fetch().arrayBuffer() in browser).
   */
  init(wasmBytes: BufferSource): void {
    if (this.initialized) return;
    initSync({ module: wasmBytes });
    this.initialized = true;
  }

  /**
   * Initialize the WASM module asynchronously. Preferred for browser use.
   * Fetches the WASM binary using import.meta.url resolution (works with bundlers).
   */
  async initAsync(): Promise<void> {
    if (this.initialized) return;
    await initWasm();
    this.initialized = true;
  }

  // ==================== Standalone Credential Operations ====================

  /**
   * Create an MLS credential with a newly generated Ed25519 signing key pair.
   * @param identityPublicKey - The user's Ed25519 identity public key (32 bytes).
   */
  createCredential(identityPublicKey: Uint8Array): MlsCredential {
    this.ensureInitialized();
    return bundleToCredential(create_credential(identityPublicKey));
  }

  /**
   * Import an existing Ed25519 signing key pair for MLS use.
   * @param identityPublicKey - The user's Ed25519 identity public key (32 bytes).
   * @param signingPrivateKey - Ed25519 private key (32-byte seed or 64-byte libsodium format).
   * @param signingPublicKey - Ed25519 public key (32 bytes).
   */
  importSigningKey(
    identityPublicKey: Uint8Array,
    signingPrivateKey: Uint8Array,
    signingPublicKey: Uint8Array,
  ): MlsCredential {
    this.ensureInitialized();
    return bundleToCredential(
      import_signing_key(identityPublicKey, signingPrivateKey, signingPublicKey),
    );
  }

  /**
   * Generate MLS KeyPackages for upload to the server (standalone, no session).
   * These cannot be used for Welcome processing since the init keys are ephemeral.
   * For group operations, use `generateSessionKeyPackages()` instead.
   */
  generateKeyPackages(credential: MlsCredential, count = 50): MlsKeyPackage[] {
    this.ensureInitialized();
    const packages: MlsKeyPackage[] = [];
    for (let i = 0; i < count; i++) {
      packages.push(
        resultToKeyPackage(
          generate_key_package(
            credential.identity,
            credential.signingPrivateKey,
            credential.signingPublicKey,
          ),
        ),
      );
    }
    return packages;
  }

  // ==================== Session Management ====================

  /**
   * Create an MLS session backed by a persistent crypto provider.
   * Groups created/joined within this session share the same provider,
   * which is required for Welcome processing (init keys must persist).
   *
   * @param credential - The MLS credential to use for this session.
   */
  createSession(credential: MlsCredential): void {
    this.ensureInitialized();
    if (this.sessionId !== null) {
      destroy_session(this.sessionId);
    }
    this.sessionId = create_session(
      credential.identity,
      credential.signingPrivateKey,
      credential.signingPublicKey,
    );
  }

  /**
   * Destroy the current session and release all crypto state.
   */
  destroySession(): void {
    if (this.sessionId !== null) {
      destroy_session(this.sessionId);
      this.sessionId = null;
    }
  }

  /**
   * Generate MLS KeyPackages within the current session.
   * Init private keys are stored in the session's provider, enabling
   * Welcome processing for groups the user is invited to.
   */
  generateSessionKeyPackages(count = 50): MlsKeyPackage[] {
    this.ensureSession();
    const packages: MlsKeyPackage[] = [];
    for (let i = 0; i < count; i++) {
      packages.push(
        resultToKeyPackage(session_generate_key_package(this.sessionId!)),
      );
    }
    return packages;
  }

  // ==================== Group Operations ====================

  /**
   * Create a new MLS group. The caller becomes the sole member.
   * @param groupId - Unique group identifier (e.g., channel UUID as bytes).
   */
  createGroup(groupId: Uint8Array): void {
    this.ensureSession();
    create_mls_group(this.sessionId!, groupId);
  }

  /**
   * Add a member to an existing MLS group.
   * @param groupId - The group to add the member to.
   * @param keyPackageTls - TLS-serialized KeyPackage of the member to add.
   * @returns Commit (broadcast to existing members) and Welcome (send to new member).
   */
  addMember(
    groupId: Uint8Array,
    keyPackageTls: Uint8Array,
  ): MlsAddMemberResult {
    this.ensureSession();
    const result: WasmAddMemberResult = add_member(
      this.sessionId!,
      groupId,
      keyPackageTls,
    );
    const out: MlsAddMemberResult = {
      commit: new Uint8Array(result.commit),
      welcome: new Uint8Array(result.welcome),
    };
    result.free();
    return out;
  }

  /**
   * Remove a member from an MLS group.
   * @param groupId - The group to remove the member from.
   * @param leafIndex - The leaf node index of the member to remove.
   * @returns TLS-serialized Commit message (broadcast to remaining members).
   */
  removeMember(groupId: Uint8Array, leafIndex: number): Uint8Array {
    this.ensureSession();
    return new Uint8Array(
      remove_member(this.sessionId!, groupId, leafIndex),
    );
  }

  /**
   * Process a Welcome message to join an MLS group.
   * Requires that the KeyPackage used in the Welcome was generated
   * within this session (via `generateSessionKeyPackages()`).
   *
   * @param welcomeTls - TLS-serialized Welcome message.
   * @returns The group ID of the joined group.
   */
  processWelcome(welcomeTls: Uint8Array): Uint8Array {
    this.ensureSession();
    return new Uint8Array(process_welcome(this.sessionId!, welcomeTls));
  }

  /**
   * Encrypt a plaintext message for the group.
   * @param groupId - The group to encrypt for.
   * @param plaintext - The message to encrypt.
   * @returns TLS-serialized MLS ciphertext.
   */
  encryptMessage(groupId: Uint8Array, plaintext: Uint8Array): Uint8Array {
    this.ensureSession();
    return new Uint8Array(
      encrypt_message(this.sessionId!, groupId, plaintext),
    );
  }

  /**
   * Process an incoming MLS group message (application, commit, or proposal).
   * For commits, the group state is automatically updated.
   * For application messages, returns the decrypted plaintext.
   */
  processMessage(
    groupId: Uint8Array,
    messageTls: Uint8Array,
  ): MlsProcessedMessage {
    this.ensureSession();
    const result: WasmProcessedMessage = process_group_message(
      this.sessionId!,
      groupId,
      messageTls,
    );
    const out: MlsProcessedMessage = {
      messageType: result.messageType,
      plaintext: new Uint8Array(result.plaintext),
      senderIdentity: new Uint8Array(result.senderIdentity),
    };
    result.free();
    return out;
  }

  // ==================== Group Inspection ====================

  /**
   * Get the current epoch of an MLS group.
   */
  getEpoch(groupId: Uint8Array): number {
    this.ensureSession();
    return Number(get_epoch(this.sessionId!, groupId));
  }

  /**
   * Get the list of members in an MLS group.
   */
  getMembers(groupId: Uint8Array): MlsGroupMember[] {
    this.ensureSession();
    const json = get_members(this.sessionId!, groupId);
    const raw = JSON.parse(json) as Array<{
      index: number;
      identity: number[];
      signature_key: number[];
    }>;
    return raw.map((m) => ({
      index: m.index,
      identity: new Uint8Array(m.identity),
      signatureKey: new Uint8Array(m.signature_key),
    }));
  }

  // ==================== Internal ====================

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error("MlsClient not initialized. Call init() first.");
    }
  }

  private ensureSession(): void {
    this.ensureInitialized();
    if (this.sessionId === null) {
      throw new Error(
        "No active MLS session. Call createSession() first.",
      );
    }
  }
}
