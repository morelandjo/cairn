/**
 * Voice store — manages voice connection state, peers, media.
 * Mobile version: stubbed initially, full implementation in Phase 7f.
 */

import { create } from "zustand";
import {
  leaveVoiceChannel,
  pushVoiceEvent,
  setVoiceCallbacks,
} from "../api/voiceSocket";
import type { VoiceStateData } from "../api/voiceSocket";

export interface VoicePeer {
  userId: string;
  muted: boolean;
  deafened: boolean;
  videoOn: boolean;
  screenSharing: boolean;
  speaking: boolean;
}

interface VoiceState {
  connected: boolean;
  channelId: string | null;
  muted: boolean;
  deafened: boolean;
  speaking: boolean;
  peers: Map<string, VoicePeer>;
  error: string | null;

  joinVoice: (channelId: string, socket: unknown) => Promise<void>;
  leaveVoice: () => void;
  toggleMute: () => void;
  toggleDeafen: () => void;
}

export const useVoiceStore = create<VoiceState>((set, get) => {
  setVoiceCallbacks({
    onPeerJoined: (data) => {
      set((state) => {
        const peers = new Map(state.peers);
        peers.set(data.userId, {
          userId: data.userId,
          muted: false,
          deafened: false,
          videoOn: false,
          screenSharing: false,
          speaking: false,
        });
        return { peers };
      });
    },

    onPeerLeft: (data) => {
      set((state) => {
        const peers = new Map(state.peers);
        peers.delete(data.userId);
        return { peers };
      });
    },

    onNewProducer: async () => {
      // Voice consumption handled in Phase 7f with react-native-webrtc
    },

    onStateUpdated: (data: VoiceStateData) => {
      set((state) => {
        const peers = new Map(state.peers);
        const existing = peers.get(data.userId);
        if (existing) {
          peers.set(data.userId, {
            ...existing,
            muted: data.muted,
            deafened: data.deafened,
            videoOn: data.videoOn,
            screenSharing: data.screenSharing,
          });
        }
        return { peers };
      });
    },

    onSpeaking: (data) => {
      set((state) => {
        const peers = new Map(state.peers);
        const existing = peers.get(data.userId);
        if (existing) {
          peers.set(data.userId, { ...existing, speaking: data.speaking });
        }
        return { peers };
      });
    },

    onModMuted: (data) => {
      set((s) => {
        const peers = new Map(s.peers);
        const existing = peers.get(data.userId);
        if (existing) {
          peers.set(data.userId, { ...existing, muted: true });
        }
        return { peers };
      });
    },

    onPeerDisconnected: (data) => {
      set((state) => {
        const peers = new Map(state.peers);
        peers.delete(data.userId);
        return { peers };
      });
    },
  });

  return {
    connected: false,
    channelId: null,
    muted: false,
    deafened: false,
    speaking: false,
    peers: new Map(),
    error: null,

    joinVoice: async (_channelId, _socket) => {
      // Full implementation in Phase 7f with react-native-webrtc
      set({ error: "Voice not yet available on mobile" });
    },

    leaveVoice: () => {
      leaveVoiceChannel();

      set({
        connected: false,
        channelId: null,
        muted: false,
        deafened: false,
        speaking: false,
        peers: new Map(),
        error: null,
      });
    },

    toggleMute: () => {
      const state = get();
      const newMuted = !state.muted;
      pushVoiceEvent("update_state", { muted: newMuted }).catch(() => {});
      set({ muted: newMuted });
    },

    toggleDeafen: () => {
      const state = get();
      const newDeafened = !state.deafened;
      const newMuted = newDeafened ? true : state.muted;
      pushVoiceEvent("update_state", {
        deafened: newDeafened,
        muted: newMuted,
      }).catch(() => {});
      set({ deafened: newDeafened, muted: newMuted });
    },
  };
});
