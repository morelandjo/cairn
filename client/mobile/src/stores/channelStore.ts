/**
 * Channel store — manages channels list, current channel, messages.
 * Mobile version: MLS E2EE not available (WASM not supported in Hermes).
 * Private channels show messages but cannot encrypt/decrypt.
 */

import { create } from "zustand";
import * as channelsApi from "../api/channels";
import * as serversApi from "../api/servers";
import type { Channel, Message, Member } from "../api/channels";
import {
  joinChannel as socketJoinChannel,
  leaveChannel as socketLeaveChannel,
  sendChannelMessage,
  setSocketCallbacks,
} from "../api/socket";
import { usePresenceStore } from "./presenceStore";

interface ChannelState {
  channels: Channel[];
  currentChannelId: string | null;
  messages: Message[];
  members: Member[];
  typingUsers: Map<string, number>;
  isLoadingChannels: boolean;
  isLoadingMessages: boolean;
  hasMoreMessages: boolean;
  replyingTo: Message | null;

  fetchChannels: (serverId?: string) => Promise<void>;
  createChannel: (name: string, type?: string, description?: string, serverId?: string) => Promise<Channel>;
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
    onMlsCommit: () => {
      // MLS not available on mobile (WASM not supported in Hermes)
    },
    onMlsWelcome: () => {
      // MLS not available on mobile
    },
    onMlsProposal: () => {
      // MLS not available on mobile
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

    createChannel: async (name, type, description, serverId) => {
      const data = serverId
        ? await serversApi.createServerChannel(serverId, { name, type, description })
        : await channelsApi.createChannel({ name, type, description });
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

      const [messagesData, membersData] = await Promise.all([
        channelsApi.getMessages(channelId, { limit: 50 }),
        channelsApi.getMembers(channelId),
      ]);

      let messages = messagesData.messages.reverse();

      // For private channels, show encrypted messages as undecryptable on mobile
      const channel = get().channels.find((c) => c.id === channelId);
      if (channel?.type === "private") {
        messages = messages.map((msg) => {
          if (msg.encrypted_content) {
            return { ...msg, content: "[E2EE not available on mobile]" };
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
        // MLS not available on mobile (WASM not supported in Hermes)
        console.warn("E2EE not available on mobile — sending plaintext");
      }

      sendChannelMessage(content, { reply_to_id: replyToId });

      if (replyTo) {
        set({ replyingTo: null });
      }
    },

    addMessage: (msg) => {
      const channel = get().channels.find(
        (c) => c.id === msg.channel_id,
      );

      if (channel?.type === "private" && msg.encrypted_content) {
        msg = { ...msg, content: "[E2EE not available on mobile]" };
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
