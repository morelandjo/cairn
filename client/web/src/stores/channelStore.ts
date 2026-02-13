/**
 * Channel store — manages channels list, current channel, messages.
 */

import { create } from "zustand";
import * as channelsApi from "../api/channels.ts";
import * as serversApi from "../api/servers.ts";
import type { Channel, Message, Member } from "../api/channels.ts";
import {
  joinChannel as socketJoinChannel,
  leaveChannel as socketLeaveChannel,
  sendChannelMessage,
  setSocketCallbacks,
} from "../api/socket.ts";
import { usePresenceStore } from "./presenceStore.ts";
import { useMlsStore } from "./mlsStore.ts";

interface ChannelState {
  channels: Channel[];
  currentChannelId: string | null;
  messages: Message[];
  members: Member[];
  typingUsers: Map<string, number>; // userId -> timestamp
  isLoadingChannels: boolean;
  isLoadingMessages: boolean;
  hasMoreMessages: boolean;
  replyingTo: Message | null;

  fetchChannels: (serverId?: string) => Promise<void>;
  createChannel: (name: string, type?: string, description?: string, serverId?: string, historyAccessible?: boolean) => Promise<Channel>;
  selectChannel: (channelId: string) => Promise<void>;
  fetchMessages: (channelId: string, before?: string) => Promise<void>;
  sendMessage: (content: string) => void;
  addMessage: (msg: Message) => void;
  updateMessage: (msg: Message) => void;
  removeMessage: (msgId: string) => void;
  setMembers: (members: Member[]) => void;
  addTypingUser: (userId: string) => void;
  setReplyingTo: (msg: Message | null) => void;
  handleReactionAdded: (data: { message_id: string; emoji: string; user_id: string }) => void;
  handleReactionRemoved: (data: { message_id: string; emoji: string; user_id: string }) => void;
}

export const useChannelStore = create<ChannelState>((set, get) => {
  // Set up socket callbacks
  setSocketCallbacks({
    onNewMessage: (msg) => {
      get().addMessage(msg as Message);
    },
    onEditMessage: (msg) => {
      get().updateMessage(msg as Message);
    },
    onDeleteMessage: (msg) => {
      const data = msg as { id: string };
      get().removeMessage(data.id);
    },
    onTyping: (data) => {
      const typingData = data as { user_id: string };
      get().addTypingUser(typingData.user_id);
    },
    onPresenceState: (state) => {
      usePresenceStore.getState().setPresenceState(state);
    },
    onPresenceDiff: (diff) => {
      usePresenceStore.getState().applyPresenceDiff(diff);
    },
    onMlsCommit: (data) => {
      const { channel_id, data: mlsData } = data as {
        channel_id: string;
        data: string;
      };
      useMlsStore.getState().processIncomingMlsMessage(channel_id, "commit", mlsData);
    },
    onMlsWelcome: (data) => {
      const { channel_id, data: mlsData } = data as {
        channel_id: string;
        data: string;
      };
      useMlsStore.getState().processIncomingMlsMessage(channel_id, "welcome", mlsData);
    },
    onMlsProposal: (data) => {
      const { channel_id, data: mlsData } = data as {
        channel_id: string;
        data: string;
      };
      useMlsStore.getState().processIncomingMlsMessage(channel_id, "proposal", mlsData);
    },
    onReactionAdded: (data) => {
      const reactionData = data as { message_id: string; emoji: string; user_id: string };
      get().handleReactionAdded(reactionData);
    },
    onReactionRemoved: (data) => {
      const reactionData = data as { message_id: string; emoji: string; user_id: string };
      get().handleReactionRemoved(reactionData);
    },
  });

  return {
    channels: [],
    currentChannelId: null,
    messages: [],
    members: [],
    typingUsers: new Map(),
    isLoadingChannels: false,
    isLoadingMessages: false,
    hasMoreMessages: true,
    replyingTo: null,

    fetchChannels: async (serverId?: string) => {
      set({ isLoadingChannels: true });
      try {
        const data = serverId
          ? await serversApi.getServerChannels(serverId)
          : await channelsApi.listChannels();
        set({ channels: data.channels, isLoadingChannels: false });
      } catch (err) {
        console.error("Failed to fetch channels:", err);
        set({ isLoadingChannels: false });
      }
    },

    createChannel: async (name, type, description, serverId, historyAccessible) => {
      const params = { name, type, description, history_accessible: historyAccessible };
      const data = serverId
        ? await serversApi.createServerChannel(serverId, params)
        : await channelsApi.createChannel(params);
      set((state) => ({ channels: [...state.channels, data.channel] }));
      return data.channel;
    },

    selectChannel: async (channelId) => {
      const prev = get().currentChannelId;
      if (prev === channelId) return;

      if (prev) {
        socketLeaveChannel();
      }

      set({
        currentChannelId: channelId,
        messages: [],
        members: [],
        hasMoreMessages: true,
        typingUsers: new Map(),
      });

      socketJoinChannel(channelId);

      // Fetch messages and members in parallel
      const [messagesData, membersData] = await Promise.all([
        channelsApi.getMessages(channelId, { limit: 50 }),
        channelsApi.getMembers(channelId),
      ]);

      // For private channels, process pending MLS messages before decrypting
      const channel = get().channels.find((c) => c.id === channelId);
      if (channel?.type === "private") {
        await useMlsStore.getState().processPendingMessages(channelId);
      }

      // Decrypt messages for private channels
      let messages = messagesData.messages.reverse();
      if (channel?.type === "private") {
        const mls = useMlsStore.getState();
        messages = messages.map((msg) => {
          if (msg.encrypted_content) {
            const decrypted = mls.decryptMessage(
              channelId,
              msg.encrypted_content,
            );
            return {
              ...msg,
              content: decrypted ?? "[Unable to decrypt]",
            };
          }
          return msg;
        });
      }

      set({
        messages,
        members: membersData.members,
        hasMoreMessages: messagesData.messages.length === 50,
      });
    },

    fetchMessages: async (channelId, before) => {
      if (get().isLoadingMessages) return;
      set({ isLoadingMessages: true });
      try {
        const data = await channelsApi.getMessages(channelId, {
          limit: 50,
          before,
        });
        const older = data.messages.reverse();
        set((state) => ({
          messages: [...older, ...state.messages],
          isLoadingMessages: false,
          hasMoreMessages: data.messages.length === 50,
        }));
      } catch (err) {
        console.error("Failed to fetch messages:", err);
        set({ isLoadingMessages: false });
      }
    },

    sendMessage: (content) => {
      const channel = get().channels.find(
        (c) => c.id === get().currentChannelId,
      );
      const replyTo = get().replyingTo;
      const replyToId = replyTo?.id;

      if (channel?.type === "private") {
        const mls = useMlsStore.getState();
        const encrypted = mls.encryptMessage(channel.id, content);
        if (encrypted) {
          sendChannelMessage(content, {
            encrypted_content: encrypted.encrypted_content,
            mls_epoch: encrypted.mls_epoch,
            reply_to_id: replyToId,
          });
        } else {
          console.error("Failed to encrypt message for private channel");
        }
      } else {
        sendChannelMessage(content, { reply_to_id: replyToId });
      }

      if (replyTo) {
        set({ replyingTo: null });
      }
    },

    addMessage: (msg) => {
      const channel = get().channels.find(
        (c) => c.id === msg.channel_id,
      );

      if (channel?.type === "private" && msg.encrypted_content) {
        const mls = useMlsStore.getState();
        const decrypted = mls.decryptMessage(
          msg.channel_id,
          msg.encrypted_content,
        );
        if (decrypted !== null) {
          msg = { ...msg, content: decrypted };
        } else {
          msg = { ...msg, content: "[Unable to decrypt]" };
        }
      }

      set((state) => ({
        messages: [...state.messages, msg],
      }));
    },

    updateMessage: (msg) => {
      set((state) => ({
        messages: state.messages.map((m) => (m.id === msg.id ? msg : m)),
      }));
    },

    removeMessage: (msgId) => {
      set((state) => ({
        messages: state.messages.filter((m) => m.id !== msgId),
      }));
    },

    setMembers: (members) => {
      set({ members });
    },

    addTypingUser: (userId) => {
      set((state) => {
        const newMap = new Map(state.typingUsers);
        newMap.set(userId, Date.now());
        return { typingUsers: newMap };
      });
      // Clear typing indicator after 3 seconds
      setTimeout(() => {
        set((state) => {
          const newMap = new Map(state.typingUsers);
          const ts = newMap.get(userId);
          if (ts && Date.now() - ts >= 2900) {
            newMap.delete(userId);
          }
          return { typingUsers: newMap };
        });
      }, 3000);
    },

    setReplyingTo: (msg) => {
      set({ replyingTo: msg });
    },

    handleReactionAdded: ({ message_id, emoji }) => {
      set((state) => ({
        messages: state.messages.map((m) => {
          if (m.id !== message_id) return m;
          const reactions = [...(m.reactions || [])];
          const existing = reactions.find((r) => r.emoji === emoji);
          if (existing) {
            existing.count += 1;
          } else {
            reactions.push({ emoji, count: 1 });
          }
          return { ...m, reactions };
        }),
      }));
    },

    handleReactionRemoved: ({ message_id, emoji }) => {
      set((state) => ({
        messages: state.messages.map((m) => {
          if (m.id !== message_id) return m;
          const reactions = (m.reactions || [])
            .map((r) => (r.emoji === emoji ? { ...r, count: r.count - 1 } : r))
            .filter((r) => r.count > 0);
          return { ...m, reactions };
        }),
      }));
    },
  };
});
