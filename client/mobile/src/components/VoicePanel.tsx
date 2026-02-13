import { View, Text, FlatList, TouchableOpacity, StyleSheet } from "react-native";
import { useVoiceStore } from "../stores/voiceStore";
import type { VoicePeer } from "../stores/voiceStore";

export function VoicePanel() {
  const { connected, muted, deafened, peers, toggleMute, toggleDeafen, leaveVoice } =
    useVoiceStore();

  if (!connected) return null;

  const peerList = Array.from(peers.values());

  const renderPeer = ({ item }: { item: VoicePeer }) => (
    <View style={styles.peerRow}>
      <View style={[styles.speakingDot, item.speaking && styles.speakingDotActive]} />
      <Text style={styles.peerName}>{item.userId.slice(0, 8)}</Text>
      {item.muted && <Text style={styles.peerStatus}>Muted</Text>}
      {item.deafened && <Text style={styles.peerStatus}>Deafened</Text>}
    </View>
  );

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Voice Connected</Text>
      <Text style={styles.warningText}>
        No E2E encryption on mobile voice
      </Text>

      <FlatList
        data={peerList}
        keyExtractor={(item) => item.userId}
        renderItem={renderPeer}
        style={styles.peerList}
        ListEmptyComponent={
          <Text style={styles.emptyText}>No other peers</Text>
        }
      />

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
          <Text style={styles.controlText}>Disconnect</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
    padding: 16,
  },
  title: {
    fontSize: 20,
    fontWeight: "bold",
    color: "#43b581",
    marginBottom: 4,
  },
  warningText: {
    color: "#ffaa00",
    fontSize: 12,
    marginBottom: 16,
  },
  peerList: {
    flex: 1,
  },
  peerRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: "#252540",
  },
  speakingDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: "#333",
    marginRight: 10,
  },
  speakingDotActive: {
    backgroundColor: "#43b581",
  },
  peerName: {
    color: "#e0e0ff",
    fontSize: 15,
    flex: 1,
  },
  peerStatus: {
    color: "#888",
    fontSize: 12,
  },
  emptyText: {
    color: "#888",
    textAlign: "center",
    marginTop: 20,
  },
  controls: {
    flexDirection: "row",
    justifyContent: "space-around",
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: "#333355",
  },
  controlButton: {
    backgroundColor: "#333355",
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 20,
  },
  controlActive: {
    backgroundColor: "#ff6b6b",
  },
  disconnectButton: {
    backgroundColor: "#ff4444",
  },
  controlText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 14,
  },
});
