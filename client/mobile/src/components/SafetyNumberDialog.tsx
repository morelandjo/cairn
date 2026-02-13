import { View, Text, Modal, TouchableOpacity, StyleSheet } from "react-native";

interface Props {
  visible: boolean;
  onClose: () => void;
  fingerprint?: string;
  peerName?: string;
}

export function SafetyNumberDialog({ visible, onClose, fingerprint, peerName }: Props) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <View style={styles.overlay}>
        <View style={styles.dialog}>
          <Text style={styles.title}>Safety Number</Text>
          <Text style={styles.subtitle}>
            Verify with {peerName ?? "this user"} that you both see the same number.
          </Text>

          <View style={styles.fingerprintBox}>
            <Text style={styles.fingerprint}>
              {fingerprint ?? "Not available on mobile\n(MLS E2EE requires desktop/web)"}
            </Text>
          </View>

          <TouchableOpacity style={styles.button} onPress={onClose}>
            <Text style={styles.buttonText}>Close</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center",
    alignItems: "center",
    padding: 32,
  },
  dialog: {
    backgroundColor: "#252540",
    borderRadius: 12,
    padding: 24,
    width: "100%",
    alignItems: "center",
  },
  title: {
    fontSize: 20,
    fontWeight: "bold",
    color: "#e0e0ff",
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: "#888",
    textAlign: "center",
    marginBottom: 20,
  },
  fingerprintBox: {
    backgroundColor: "#1a1a2e",
    borderRadius: 8,
    padding: 16,
    width: "100%",
    marginBottom: 20,
  },
  fingerprint: {
    color: "#e0e0ff",
    fontSize: 14,
    textAlign: "center",
    fontFamily: "monospace",
    lineHeight: 22,
  },
  button: {
    backgroundColor: "#5865f2",
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 32,
  },
  buttonText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 15,
  },
});
