import { View, Text, StyleSheet, TouchableOpacity } from "react-native";
import type { Message } from "../api/channels";
import { useChannelStore } from "../stores/channelStore";
import { ReactionPicker } from "./ReactionPicker";
import { useState } from "react";

interface Props {
  message: Message;
}

export function MessageBubble({ message }: Props) {
  const setReplyingTo = useChannelStore((s) => s.setReplyingTo);
  const [showReactions, setShowReactions] = useState(false);

  const timestamp = new Date(message.inserted_at).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });

  return (
    <TouchableOpacity
      style={styles.container}
      onLongPress={() => setShowReactions(!showReactions)}
      activeOpacity={0.8}
    >
      {message.reply_to && (
        <View style={styles.replyIndicator}>
          <Text style={styles.replyUsername} numberOfLines={1}>
            {message.reply_to.author_username}
          </Text>
          <Text style={styles.replyContent} numberOfLines={1}>
            {message.reply_to.content}
          </Text>
        </View>
      )}

      <View style={styles.header}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>
            {(message.author_display_name ?? message.author_username ?? "?")[0].toUpperCase()}
          </Text>
        </View>
        <View style={styles.headerInfo}>
          <Text style={styles.username}>
            {message.author_display_name ?? message.author_username}
            {message.is_bot && <Text style={styles.botBadge}> BOT</Text>}
          </Text>
          <Text style={styles.timestamp}>{timestamp}</Text>
        </View>
      </View>

      <Text style={styles.content}>{message.content ?? "[No content]"}</Text>

      {message.edited_at && (
        <Text style={styles.edited}>(edited)</Text>
      )}

      {message.reactions && message.reactions.length > 0 && (
        <View style={styles.reactions}>
          {message.reactions.map((r) => (
            <View key={r.emoji} style={styles.reactionBadge}>
              <Text style={styles.reactionEmoji}>{r.emoji}</Text>
              <Text style={styles.reactionCount}>{r.count}</Text>
            </View>
          ))}
        </View>
      )}

      {showReactions && (
        <ReactionPicker
          messageId={message.id}
          channelId={message.channel_id}
          onClose={() => setShowReactions(false)}
        />
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  replyIndicator: {
    flexDirection: "row",
    paddingLeft: 40,
    marginBottom: 4,
    opacity: 0.6,
  },
  replyUsername: {
    color: "#5865f2",
    fontSize: 12,
    fontWeight: "600",
    marginRight: 6,
  },
  replyContent: {
    color: "#888",
    fontSize: 12,
    flex: 1,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 4,
  },
  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: "#5865f2",
    justifyContent: "center",
    alignItems: "center",
    marginRight: 8,
  },
  avatarText: {
    color: "#fff",
    fontWeight: "bold",
    fontSize: 14,
  },
  headerInfo: {
    flexDirection: "row",
    alignItems: "baseline",
    flex: 1,
  },
  username: {
    color: "#e0e0ff",
    fontWeight: "600",
    fontSize: 15,
    marginRight: 8,
  },
  botBadge: {
    color: "#5865f2",
    fontSize: 10,
    fontWeight: "bold",
  },
  timestamp: {
    color: "#666",
    fontSize: 11,
  },
  content: {
    color: "#ccc",
    fontSize: 15,
    lineHeight: 21,
    paddingLeft: 40,
  },
  edited: {
    color: "#666",
    fontSize: 11,
    paddingLeft: 40,
  },
  reactions: {
    flexDirection: "row",
    flexWrap: "wrap",
    paddingLeft: 40,
    marginTop: 4,
    gap: 4,
  },
  reactionBadge: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#252540",
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  reactionEmoji: {
    fontSize: 14,
    marginRight: 4,
  },
  reactionCount: {
    color: "#888",
    fontSize: 12,
  },
});
