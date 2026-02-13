/**
 * Voice channel Phoenix Channel wrapper.
 * Handles join, produce, consume, and state events for voice channels.
 */

// @ts-expect-error phoenix has no type declarations
import { Socket } from "phoenix";

/* eslint-disable @typescript-eslint/no-explicit-any */

export interface VoiceJoinResponse {
  rtpCapabilities: any;
  sendTransport: {
    id: string;
    iceParameters: any;
    iceCandidates: any[];
    dtlsParameters: any;
  };
  recvTransport: {
    id: string;
    iceParameters: any;
    iceCandidates: any[];
    dtlsParameters: any;
  };
  voiceState: VoiceStateData;
  peers: VoiceStateData[];
}

export interface VoiceStateData {
  userId: string;
  channelId: string;
  muted: boolean;
  deafened: boolean;
  videoOn: boolean;
  screenSharing: boolean;
}

export interface VoiceCallbacks {
  onPeerJoined?: (data: { userId: string }) => void;
  onPeerLeft?: (data: { userId: string }) => void;
  onNewProducer?: (data: {
    producerId: string;
    userId: string;
    kind: string;
    appData: Record<string, unknown>;
  }) => void;
  onStateUpdated?: (data: VoiceStateData) => void;
  onSpeaking?: (data: { userId: string; speaking: boolean }) => void;
  onModMuted?: (data: { userId: string; by: string }) => void;
  onPeerDisconnected?: (data: { userId: string; by: string }) => void;
}

let voiceChannel: any = null;
let voiceCallbacks: VoiceCallbacks = {};

export function setVoiceCallbacks(cb: VoiceCallbacks) {
  voiceCallbacks = cb;
}

export function joinVoiceChannel(
  socket: any,
  channelId: string,
): Promise<VoiceJoinResponse> {
  return new Promise((resolve, reject) => {
    if (voiceChannel) {
      voiceChannel.leave();
    }

    voiceChannel = socket.channel(`voice:${channelId}`, {});

    voiceChannel.on("peer_joined", (data: any) => {
      voiceCallbacks.onPeerJoined?.(data);
    });

    voiceChannel.on("peer_left", (data: any) => {
      voiceCallbacks.onPeerLeft?.(data);
    });

    voiceChannel.on("new_producer", (data: any) => {
      voiceCallbacks.onNewProducer?.(data);
    });

    voiceChannel.on("state_updated", (data: any) => {
      voiceCallbacks.onStateUpdated?.(data);
    });

    voiceChannel.on("speaking", (data: any) => {
      voiceCallbacks.onSpeaking?.(data);
    });

    voiceChannel.on("mod_muted", (data: any) => {
      voiceCallbacks.onModMuted?.(data);
    });

    voiceChannel.on("peer_disconnected", (data: any) => {
      voiceCallbacks.onPeerDisconnected?.(data);
    });

    voiceChannel
      .join()
      .receive("ok", (resp: VoiceJoinResponse) => {
        resolve(resp);
      })
      .receive("error", (resp: any) => {
        voiceChannel = null;
        reject(new Error(resp?.reason || "Failed to join voice channel"));
      });
  });
}

export function pushVoiceEvent(
  event: string,
  payload: any,
): Promise<any> {
  return new Promise((resolve, reject) => {
    if (!voiceChannel) {
      reject(new Error("Not in a voice channel"));
      return;
    }

    voiceChannel
      .push(event, payload)
      .receive("ok", (resp: any) => resolve(resp))
      .receive("error", (resp: any) =>
        reject(new Error(resp?.reason || `Voice event ${event} failed`)),
      );
  });
}

export function leaveVoiceChannel() {
  if (voiceChannel) {
    voiceChannel.leave();
    voiceChannel = null;
  }
}

export function getVoiceChannel() {
  return voiceChannel;
}

/* eslint-enable @typescript-eslint/no-explicit-any */
