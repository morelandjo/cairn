import { useState, useRef } from "react";
import {
  View,
  TextInput,
  TouchableOpacity,
  Text,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from "react-native";
import type { Message } from "../api/channels";
import { sendTyping } from "../api/socket";

interface Props {
  onSend: (content: string) => void;
  replyingTo: Message | null;
  onCancelReply: () => void;
  isPrivate?: boolean;
}

export function MessageInput({ onSend, replyingTo, onCancelReply, isPrivate }: Props) {
  const [text, setText] = useState("");
  const lastTypingSent = useRef(0);

  const handleChangeText = (value: string) => {
    setText(value);
    const now = Date.now();
    if (now - lastTypingSent.current > 2000) {
      sendTyping();
      lastTypingSent.current = now;
    }
  };

  const handleSend = () => {
    const content = text.trim();
    if (!content) return;
    onSend(content);
    setText("");
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : undefined}
      keyboardVerticalOffset={0}
    >
      {replyingTo && (
        <View style={styles.replyBar}>
          <Text style={styles.replyText} numberOfLines={1}>
            Replying to {replyingTo.author_username}
          </Text>
          <TouchableOpacity onPress={onCancelReply}>
            <Text style={styles.replyCancelText}>X</Text>
          </TouchableOpacity>
        </View>
      )}

      {isPrivate && (
        <View style={styles.warningBar}>
          <Text style={styles.warningText}>
            E2EE not available on mobile
          </Text>
        </View>
      )}

      <View style={styles.container}>
        <TextInput
          style={styles.input}
          value={text}
          onChangeText={handleChangeText}
          placeholder="Type a message..."
          placeholderTextColor="#666"
          multiline
          maxLength={4000}
          returnKeyType="default"
        />
        <TouchableOpacity
          style={[styles.sendButton, !text.trim() && styles.sendButtonDisabled]}
          onPress={handleSend}
          disabled={!text.trim()}
        >
          <Text style={styles.sendText}>Send</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "flex-end",
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: "#16162a",
    borderTopWidth: 1,
    borderTopColor: "#333355",
  },
  input: {
    flex: 1,
    backgroundColor: "#252540",
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    color: "#e0e0ff",
    fontSize: 16,
    maxHeight: 120,
  },
  sendButton: {
    backgroundColor: "#5865f2",
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    marginLeft: 8,
    justifyContent: "center",
  },
  sendButtonDisabled: {
    opacity: 0.4,
  },
  sendText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 15,
  },
  replyBar: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: "#252540",
    borderTopWidth: 1,
    borderTopColor: "#333355",
  },
  replyText: {
    flex: 1,
    color: "#888",
    fontSize: 13,
  },
  replyCancelText: {
    color: "#ff6b6b",
    fontSize: 16,
    fontWeight: "bold",
    paddingLeft: 12,
  },
  warningBar: {
    paddingHorizontal: 16,
    paddingVertical: 4,
    backgroundColor: "#443300",
  },
  warningText: {
    color: "#ffaa00",
    fontSize: 12,
    textAlign: "center",
  },
});
