/**
 * Voice store — manages voice connection state, peers, media.
 */

import { create } from "zustand";
import { MediasoupManager } from "../lib/mediasoupClient.ts";
import { AudioAnalyser } from "../lib/audioAnalyser.ts";
import {
  joinVoiceChannel,
  leaveVoiceChannel,
  pushVoiceEvent,
  setVoiceCallbacks,
} from "../api/voiceSocket.ts";
import type { VoiceStateData } from "../api/voiceSocket.ts";

export interface VoicePeer {
  userId: string;
  muted: boolean;
  deafened: boolean;
  videoOn: boolean;
  screenSharing: boolean;
  speaking: boolean;
  audioTrack?: MediaStreamTrack;
  videoTrack?: MediaStreamTrack;
}

interface VoiceState {
  connected: boolean;
  channelId: string | null;
  muted: boolean;
  deafened: boolean;
  videoOn: boolean;
  screenSharing: boolean;
  speaking: boolean;
  peers: Map<string, VoicePeer>;
  localStream: MediaStream | null;
  error: string | null;

  joinVoice: (channelId: string, socket: unknown) => Promise<void>;
  leaveVoice: () => void;
  toggleMute: () => void;
  toggleDeafen: () => void;
}

let manager: MediasoupManager | null = null;
let analyser: AudioAnalyser | null = null;

export const useVoiceStore = create<VoiceState>((set, get) => {
  // Set up voice channel callbacks
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
        const peer = peers.get(data.userId);
        if (peer) {
          peer.audioTrack?.stop();
          peer.videoTrack?.stop();
        }
        peers.delete(data.userId);
        return { peers };
      });
    },

    onNewProducer: async (data) => {
      if (!manager?.loaded) return;
      try {
        const consumer = await manager.consume({
          producerId: data.producerId,
          rtpCapabilities: manager.rtpCapabilities,
        });

        set((state) => {
          const peers = new Map(state.peers);
          const peer = peers.get(data.userId) || {
            userId: data.userId,
            muted: false,
            deafened: false,
            videoOn: false,
            screenSharing: false,
            speaking: false,
          };

          if (consumer.kind === "audio") {
            // Attach audio to an <audio> element for playback
            const audio = new Audio();
            audio.srcObject = new MediaStream([consumer.track]);
            audio.play().catch(() => {});
            peer.audioTrack = consumer.track;
          } else {
            peer.videoTrack = consumer.track;
          }

          peers.set(data.userId, { ...peer });
          return { peers };
        });
      } catch (err) {
        console.error("Failed to consume producer:", err);
      }
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
      const state = get();
      // If we were mod-muted, update our local state
      if (data.userId === state.channelId) {
        // Actually check against our user ID — need to pass it in
      }
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
        const peer = peers.get(data.userId);
        if (peer) {
          peer.audioTrack?.stop();
          peer.videoTrack?.stop();
        }
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
    videoOn: false,
    screenSharing: false,
    speaking: false,
    peers: new Map(),
    localStream: null,
    error: null,

    joinVoice: async (channelId, socket) => {
      try {
        set({ error: null });

        // Join the voice Phoenix channel
        const response = await joinVoiceChannel(socket, channelId);

        // Create mediasoup manager
        manager = new MediasoupManager();
        await manager.loadDevice(response.rtpCapabilities);

        // Create transports
        manager.createSendTransport(response.sendTransport);
        manager.createRecvTransport(response.recvTransport);

        // Get user microphone
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
          video: false,
        });

        // Produce audio
        const audioTrack = stream.getAudioTracks()[0];
        if (audioTrack) {
          await manager.produce(audioTrack, { source: "mic" });
        }

        // Set up speaking detection
        analyser = new AudioAnalyser((speaking) => {
          set({ speaking });
          pushVoiceEvent("speaking", { speaking }).catch(() => {});
        });
        analyser.start(stream);

        // Set initial peer states
        const peers = new Map<string, VoicePeer>();
        for (const peerState of response.peers) {
          peers.set(peerState.userId, {
            userId: peerState.userId,
            muted: peerState.muted,
            deafened: peerState.deafened,
            videoOn: peerState.videoOn,
            screenSharing: peerState.screenSharing,
            speaking: false,
          });
        }

        set({
          connected: true,
          channelId,
          localStream: stream,
          peers,
        });
      } catch (err) {
        console.error("Failed to join voice:", err);
        set({
          error: err instanceof Error ? err.message : "Failed to join voice",
        });
      }
    },

    leaveVoice: () => {
      const state = get();

      // Stop local media
      state.localStream?.getTracks().forEach((t) => t.stop());

      // Stop speaking analyser
      analyser?.stop();
      analyser = null;

      // Close mediasoup
      manager?.close();
      manager = null;

      // Leave Phoenix voice channel
      leaveVoiceChannel();

      // Clean up peer tracks
      for (const peer of state.peers.values()) {
        peer.audioTrack?.stop();
        peer.videoTrack?.stop();
      }

      set({
        connected: false,
        channelId: null,
        muted: false,
        deafened: false,
        videoOn: false,
        screenSharing: false,
        speaking: false,
        peers: new Map(),
        localStream: null,
        error: null,
      });
    },

    toggleMute: () => {
      const state = get();
      const newMuted = !state.muted;

      // Mute/unmute local audio track
      if (state.localStream) {
        for (const track of state.localStream.getAudioTracks()) {
          track.enabled = !newMuted;
        }
      }

      // Also pause/resume the producer on the SFU
      if (manager) {
        const audioProducer = manager.getProducerByKind("audio");
        if (audioProducer) {
          if (newMuted) {
            audioProducer.pause();
          } else {
            audioProducer.resume();
          }
        }
      }

      // Update server state
      pushVoiceEvent("update_state", { muted: newMuted }).catch(() => {});

      set({ muted: newMuted });
    },

    toggleDeafen: () => {
      const state = get();
      const newDeafened = !state.deafened;

      // When deafening, also mute
      const newMuted = newDeafened ? true : state.muted;

      // Mute all incoming audio consumer tracks
      for (const consumer of manager?.allConsumers.values() ?? []) {
        if (consumer.kind === "audio") {
          consumer.track.enabled = !newDeafened;
        }
      }

      // Also mute local audio
      if (state.localStream && newDeafened) {
        for (const track of state.localStream.getAudioTracks()) {
          track.enabled = false;
        }
      }

      pushVoiceEvent("update_state", {
        deafened: newDeafened,
        muted: newMuted,
      }).catch(() => {});

      set({ deafened: newDeafened, muted: newMuted });
    },
  };
});
