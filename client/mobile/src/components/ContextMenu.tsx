import { View, Text, TouchableOpacity, Modal, StyleSheet } from "react-native";
import type { Message } from "../api/channels";
import { useChannelStore } from "../stores/channelStore";

interface Props {
  visible: boolean;
  message: Message;
  onClose: () => void;
}

export function ContextMenu({ visible, message, onClose }: Props) {
  const setReplyingTo = useChannelStore((s) => s.setReplyingTo);

  const handleReply = () => {
    setReplyingTo(message);
    onClose();
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <TouchableOpacity style={styles.overlay} activeOpacity={1} onPress={onClose}>
        <View style={styles.menu}>
          <TouchableOpacity style={styles.menuItem} onPress={handleReply}>
            <Text style={styles.menuText}>Reply</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.menuItem} onPress={onClose}>
            <Text style={styles.menuText}>Copy Text</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.menuItem} onPress={onClose}>
            <Text style={[styles.menuText, styles.menuTextDanger]}>Delete</Text>
          </TouchableOpacity>
        </View>
      </TouchableOpacity>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center",
    alignItems: "center",
  },
  menu: {
    backgroundColor: "#252540",
    borderRadius: 12,
    width: 220,
    overflow: "hidden",
  },
  menuItem: {
    paddingVertical: 14,
    paddingHorizontal: 20,
    borderBottomWidth: 1,
    borderBottomColor: "#333355",
  },
  menuText: {
    color: "#e0e0ff",
    fontSize: 16,
  },
  menuTextDanger: {
    color: "#ff6b6b",
  },
});
