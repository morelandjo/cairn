import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { useVoiceStore } from "../stores/voiceStore";

/**
 * Persistent notification bar shown when user is in a voice channel.
 * Displayed at the top of screens that aren't the voice panel.
 */
export function InCallNotification() {
  const { connected, channelId, leaveVoice } = useVoiceStore();

  if (!connected) return null;

  return (
    <View style={styles.container}>
      <View style={styles.indicator} />
      <Text style={styles.text}>In Voice: {channelId?.slice(0, 8)}...</Text>
      <TouchableOpacity onPress={leaveVoice} style={styles.leaveButton}>
        <Text style={styles.leaveText}>Leave</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: "#43b581",
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 6,
    paddingHorizontal: 16,
  },
  indicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: "#fff",
    marginRight: 8,
  },
  text: {
    flex: 1,
    color: "#fff",
    fontSize: 13,
    fontWeight: "600",
  },
  leaveButton: {
    backgroundColor: "rgba(0,0,0,0.2)",
    borderRadius: 4,
    paddingVertical: 4,
    paddingHorizontal: 10,
  },
  leaveText: {
    color: "#fff",
    fontSize: 12,
    fontWeight: "600",
  },
});
