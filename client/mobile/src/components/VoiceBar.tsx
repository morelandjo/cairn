import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { useVoiceStore } from "../stores/voiceStore";

export function VoiceBar() {
  const { connected, muted, deafened, leaveVoice, toggleMute, toggleDeafen } = useVoiceStore();

  if (!connected) return null;

  return (
    <View style={styles.container}>
      <Text style={styles.statusText}>In Voice Channel</Text>

      <View style={styles.controls}>
        <TouchableOpacity
          style={[styles.controlButton, muted && styles.controlActive]}
          onPress={toggleMute}
        >
          <Text style={styles.controlText}>{muted ? "Unmute" : "Mute"}</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.controlButton, deafened && styles.controlActive]}
          onPress={toggleDeafen}
        >
          <Text style={styles.controlText}>{deafened ? "Undeaf" : "Deafen"}</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.controlButton, styles.disconnectButton]}
          onPress={leaveVoice}
        >
          <Text style={styles.controlText}>Leave</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: "#252540",
    paddingVertical: 8,
    paddingHorizontal: 16,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    borderTopWidth: 1,
    borderTopColor: "#333355",
  },
  statusText: {
    color: "#43b581",
    fontSize: 13,
    fontWeight: "600",
  },
  controls: {
    flexDirection: "row",
    gap: 8,
  },
  controlButton: {
    backgroundColor: "#333355",
    borderRadius: 6,
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  controlActive: {
    backgroundColor: "#ff6b6b",
  },
  disconnectButton: {
    backgroundColor: "#ff4444",
  },
  controlText: {
    color: "#fff",
    fontSize: 12,
    fontWeight: "600",
  },
});
