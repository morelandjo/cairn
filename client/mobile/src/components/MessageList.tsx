import { FlatList, ActivityIndicator, StyleSheet, View, Text } from "react-native";
import type { Message } from "../api/channels";
import { MessageBubble } from "./MessageBubble";

interface Props {
  messages: Message[];
  isLoading: boolean;
  onLoadMore: () => void;
}

export function MessageList({ messages, isLoading, onLoadMore }: Props) {
  return (
    <FlatList
      data={messages}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => <MessageBubble message={item} />}
      inverted={false}
      contentContainerStyle={styles.list}
      onStartReached={onLoadMore}
      onStartReachedThreshold={0.5}
      ListHeaderComponent={
        isLoading ? <ActivityIndicator color="#5865f2" style={styles.loader} /> : null
      }
      ListEmptyComponent={
        !isLoading ? (
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>No messages yet</Text>
          </View>
        ) : null
      }
      maintainVisibleContentPosition={{ minIndexForVisible: 0 }}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    paddingVertical: 8,
    flexGrow: 1,
  },
  loader: {
    padding: 12,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    paddingVertical: 40,
  },
  emptyText: {
    color: "#888",
    fontSize: 15,
  },
});
