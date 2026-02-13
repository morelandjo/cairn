import { useEffect } from "react";
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useChannelStore } from "@/stores/channelStore";
import { MessageList } from "@/components/MessageList";
import { MessageInput } from "@/components/MessageInput";
import { TypingIndicator } from "@/components/TypingIndicator";
import { VoiceBar } from "@/components/VoiceBar";
import { useVoiceStore } from "@/stores/voiceStore";

export default function ChannelScreen() {
  const { channelId } = useLocalSearchParams<{ channelId: string }>();
  const router = useRouter();
  const {
    channels,
    messages,
    isLoadingMessages,
    hasMoreMessages,
    typingUsers,
    selectChannel,
    fetchMessages,
    sendMessage,
    replyingTo,
    setReplyingTo,
  } = useChannelStore();
  const voiceConnected = useVoiceStore((s) => s.connected);

  const channel = channels.find((c) => c.id === channelId);

  useEffect(() => {
    if (channelId) {
      selectChannel(channelId);
    }
  }, [channelId, selectChannel]);

  const handleLoadMore = () => {
    if (!channelId || !hasMoreMessages || isLoadingMessages) return;
    const oldest = messages[0];
    if (oldest) {
      fetchMessages(channelId, oldest.id);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Text style={styles.backText}>{"<"}</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitle} numberOfLines={1}>
          #{channel?.name ?? "..."}
        </Text>
        {channel?.type === "private" && (
          <Text style={styles.lockIcon}>E2EE</Text>
        )}
      </View>

      <MessageList
        messages={messages}
        isLoading={isLoadingMessages}
        onLoadMore={handleLoadMore}
      />

      <TypingIndicator typingUsers={typingUsers} />

      {voiceConnected && <VoiceBar />}

      <MessageInput
        onSend={sendMessage}
        replyingTo={replyingTo}
        onCancelReply={() => setReplyingTo(null)}
        isPrivate={channel?.type === "private"}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingTop: 56,
    paddingBottom: 12,
    backgroundColor: "#16162a",
    borderBottomWidth: 1,
    borderBottomColor: "#333355",
  },
  backButton: {
    marginRight: 12,
    padding: 4,
  },
  backText: {
    color: "#5865f2",
    fontSize: 20,
    fontWeight: "bold",
  },
  headerTitle: {
    flex: 1,
    fontSize: 18,
    fontWeight: "600",
    color: "#e0e0ff",
  },
  lockIcon: {
    fontSize: 12,
    color: "#43b581",
    marginLeft: 8,
    fontWeight: "600",
  },
});
