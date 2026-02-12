/**
 * MLS store — manages MLS group encryption state for private channels.
 *
 * Handles WASM initialization, MLS session lifecycle, KeyPackage management,
 * and encrypt/decrypt operations for private channel messages.
 */

import { create } from "zustand";
import { MlsClient } from "@cairn/proto";
import type { MlsCredential } from "@cairn/proto";
import * as mlsApi from "../api/mls.ts";
import * as channelsApi from "../api/channels.ts";

const MIN_KEY_PACKAGES = 10;
const KEY_PACKAGE_BATCH = 50;

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

function channelIdToGroupId(channelId: string): Uint8Array {
  return textEncoder.encode(channelId);
}

function base64Encode(data: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < data.length; i++) {
    binary += String.fromCharCode(data[i]);
  }
  return btoa(binary);
}

function base64Decode(str: string): Uint8Array {
  const binary = atob(str);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

interface MlsState {
  initialized: boolean;
  credential: MlsCredential | null;
  error: string | null;

  /** Initialize MLS: load WASM, create credential + session. */
  initMls: (identityKeyPair: {
    publicKey: Uint8Array;
    privateKey: Uint8Array;
  }) => Promise<void>;

  /** Ensure sufficient KeyPackages are uploaded to the server. */
  ensureKeyPackages: () => Promise<void>;

  /** Create a private channel and set up MLS group with initial members. */
  createPrivateChannel: (
    name: string,
    memberIds: string[],
  ) => Promise<channelsApi.Channel>;

  /** Invite a user to an existing private channel's MLS group. */
  inviteMember: (channelId: string, userId: string) => Promise<void>;

  /** Encrypt a plaintext message for a private channel. */
  encryptMessage: (
    channelId: string,
    plaintext: string,
  ) => { encrypted_content: string; mls_epoch: number } | null;

  /** Decrypt an encrypted message from a private channel. */
  decryptMessage: (
    channelId: string,
    encryptedContent: string,
  ) => string | null;

  /** Process an incoming MLS protocol message (commit/welcome/proposal). */
  processIncomingMlsMessage: (
    channelId: string,
    messageType: string,
    data: string,
  ) => void;

  /** Fetch and process any pending MLS messages for a channel. */
  processPendingMessages: (channelId: string) => Promise<void>;

  /** Tear down MLS state on logout. */
  destroy: () => void;
}

// Singleton MlsClient instance (lives outside store for stability)
let mlsClient: MlsClient | null = null;

export const useMlsStore = create<MlsState>((set, get) => ({
  initialized: false,
  credential: null,
  error: null,

  initMls: async (identityKeyPair) => {
    try {
      if (get().initialized) return;

      // Initialize WASM asynchronously (bundler resolves the .wasm file)
      mlsClient = new MlsClient();
      await mlsClient.initAsync();

      // Create MLS credential from identity keys
      const credential = mlsClient.importSigningKey(
        identityKeyPair.publicKey,
        identityKeyPair.privateKey,
        identityKeyPair.publicKey,
      );

      // Create session for group operations
      mlsClient.createSession(credential);

      set({ initialized: true, credential, error: null });

      // Upload KeyPackages in background
      get().ensureKeyPackages().catch(console.error);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "MLS initialization failed";
      console.error("MLS init failed:", err);
      set({ error: message });
    }
  },

  ensureKeyPackages: async () => {
    if (!mlsClient || !get().initialized) return;

    try {
      const { count } = await mlsApi.keyPackageCount();
      if (count >= MIN_KEY_PACKAGES) return;

      const packages = mlsClient.generateSessionKeyPackages(KEY_PACKAGE_BATCH);
      const encoded = packages.map((pkg) => base64Encode(pkg.keyPackageData));
      await mlsApi.uploadKeyPackages(encoded);
    } catch (err) {
      console.error("Failed to ensure KeyPackages:", err);
    }
  },

  createPrivateChannel: async (name, memberIds) => {
    if (!mlsClient || !get().initialized) {
      throw new Error("MLS not initialized");
    }

    // Create the channel on the server
    const { channel } = await channelsApi.createChannel({
      name,
      type: "private",
    });

    const groupId = channelIdToGroupId(channel.id);

    // Create MLS group
    mlsClient.createGroup(groupId);

    // Add each member
    for (const memberId of memberIds) {
      try {
        // Claim a KeyPackage for this member
        const { key_package } = await mlsApi.claimKeyPackage(memberId);
        if (!key_package) {
          console.warn(
            `No KeyPackage available for user ${memberId}, skipping`,
          );
          continue;
        }

        const keyPackageBytes = base64Decode(key_package);
        const result = mlsClient.addMember(groupId, keyPackageBytes);

        // Store commit for existing members
        const epoch = mlsClient.getEpoch(groupId);
        await mlsApi.storeCommit(
          channel.id,
          base64Encode(result.commit),
          epoch,
        );

        // Send welcome to new member
        await mlsApi.storeWelcome(
          channel.id,
          base64Encode(result.welcome),
          memberId,
        );
      } catch (err) {
        console.error(`Failed to add member ${memberId}:`, err);
      }
    }

    // Store group info for late joiners
    const epoch = mlsClient.getEpoch(groupId);
    await mlsApi.storeGroupInfo(channel.id, base64Encode(groupId), epoch);

    return channel;
  },

  inviteMember: async (channelId, userId) => {
    if (!mlsClient || !get().initialized) {
      throw new Error("MLS not initialized");
    }

    const groupId = channelIdToGroupId(channelId);

    // Claim KeyPackage
    const { key_package } = await mlsApi.claimKeyPackage(userId);
    if (!key_package) {
      throw new Error(`No KeyPackage available for user ${userId}`);
    }

    const keyPackageBytes = base64Decode(key_package);
    const result = mlsClient.addMember(groupId, keyPackageBytes);

    const epoch = mlsClient.getEpoch(groupId);

    // Store commit + welcome on server
    await Promise.all([
      mlsApi.storeCommit(channelId, base64Encode(result.commit), epoch),
      mlsApi.storeWelcome(channelId, base64Encode(result.welcome), userId),
    ]);
  },

  encryptMessage: (channelId, plaintext) => {
    if (!mlsClient || !get().initialized) return null;

    try {
      const groupId = channelIdToGroupId(channelId);
      const plaintextBytes = textEncoder.encode(plaintext);
      const ciphertext = mlsClient.encryptMessage(groupId, plaintextBytes);
      const epoch = mlsClient.getEpoch(groupId);

      return {
        encrypted_content: base64Encode(ciphertext),
        mls_epoch: epoch,
      };
    } catch (err) {
      console.error("MLS encrypt failed:", err);
      return null;
    }
  },

  decryptMessage: (channelId, encryptedContent) => {
    if (!mlsClient || !get().initialized) return null;

    try {
      const groupId = channelIdToGroupId(channelId);
      const ciphertextBytes = base64Decode(encryptedContent);
      const result = mlsClient.processMessage(groupId, ciphertextBytes);

      if (result.messageType === "application") {
        return textDecoder.decode(result.plaintext);
      }
      return null;
    } catch (err) {
      console.error("MLS decrypt failed:", err);
      return null;
    }
  },

  processIncomingMlsMessage: (channelId, messageType, data) => {
    if (!mlsClient || !get().initialized) return;

    try {
      const groupId = channelIdToGroupId(channelId);
      const bytes = base64Decode(data);

      switch (messageType) {
        case "welcome": {
          mlsClient.processWelcome(bytes);
          break;
        }
        case "commit":
        case "proposal": {
          mlsClient.processMessage(groupId, bytes);
          break;
        }
        default:
          console.warn(`Unknown MLS message type: ${messageType}`);
      }
    } catch (err) {
      console.error(`Failed to process MLS ${messageType}:`, err);
    }
  },

  processPendingMessages: async (channelId) => {
    if (!mlsClient || !get().initialized) return;

    try {
      const { messages } = await mlsApi.getPendingMessages(channelId);
      if (messages.length === 0) return;

      const processedIds: string[] = [];

      for (const msg of messages) {
        try {
          get().processIncomingMlsMessage(
            channelId,
            msg.message_type,
            msg.data,
          );
          processedIds.push(msg.id);
        } catch (err) {
          console.error(`Failed to process MLS message ${msg.id}:`, err);
        }
      }

      if (processedIds.length > 0) {
        await mlsApi.ackMessages(channelId, processedIds);
      }
    } catch (err) {
      console.error("Failed to process pending MLS messages:", err);
    }
  },

  destroy: () => {
    if (mlsClient) {
      mlsClient.destroySession();
      mlsClient = null;
    }
    set({ initialized: false, credential: null, error: null });
  },
}));
