/**
 * iOS/Android audio session configuration for voice chat.
 * Configures audio routing for speaker, earpiece, and Bluetooth.
 */

import { Platform } from "react-native";

/**
 * Configure the audio session for voice chat.
 * On iOS, sets the audio category to PlayAndRecord with VoiceChat mode.
 * On Android, no extra configuration needed — WebRTC handles it.
 */
export async function configureAudioSession(): Promise<void> {
  if (Platform.OS === "ios") {
    try {
      // react-native-webrtc provides AudioSession on iOS
      const { AudioSession } = await import("react-native-webrtc");
      if (AudioSession?.configure) {
        await AudioSession.configure({
          category: "PlayAndRecord",
          mode: "VoiceChat",
          options: ["DefaultToSpeaker", "AllowBluetooth"],
        });
      }
    } catch (err) {
      console.warn("Failed to configure iOS audio session:", err);
    }
  }
  // Android: WebRTC handles audio routing automatically
}

/**
 * Reset the audio session when leaving voice.
 */
export async function resetAudioSession(): Promise<void> {
  if (Platform.OS === "ios") {
    try {
      const { AudioSession } = await import("react-native-webrtc");
      if (AudioSession?.configure) {
        await AudioSession.configure({
          category: "Ambient",
          mode: "Default",
          options: [],
        });
      }
    } catch {
      // Ignore
    }
  }
}
