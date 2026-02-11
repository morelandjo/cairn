import { useEffect } from "react";
import { View, Text, FlatList, TouchableOpacity, StyleSheet, ActivityIndicator } from "react-native";
import { useRouter } from "expo-router";
import { useChannelStore } from "@/stores/channelStore";

export default function DMListScreen() {
  const router = useRouter();
  const { channels, fetchChannels, isLoadingChannels } = useChannelStore();

  useEffect(() => {
    fetchChannels(); // No serverId = flat/DM channels
  }, [fetchChannels]);

  const dmChannels = channels.filter((c) => c.type === "dm" || c.type === "private");

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Direct Messages</Text>
      </View>

      {isLoadingChannels ? (
        <ActivityIndicator color="#5865f2" style={styles.loader} />
      ) : (
        <FlatList
          data={dmChannels}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <TouchableOpacity
              style={styles.item}
              onPress={() => router.push(`/(app)/(tabs)/channels/${item.id}`)}
            >
              <Text style={styles.channelName}>{item.name}</Text>
              {item.type === "private" && (
                <Text style={styles.lockBadge}>E2EE</Text>
              )}
            </TouchableOpacity>
          )}
          ListEmptyComponent={
            <Text style={styles.empty}>No direct messages yet</Text>
          }
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 56,
    paddingBottom: 12,
    backgroundColor: "#16162a",
    borderBottomWidth: 1,
    borderBottomColor: "#333355",
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: "bold",
    color: "#e0e0ff",
  },
  loader: {
    marginTop: 40,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: "#252540",
  },
  channelName: {
    flex: 1,
    fontSize: 16,
    color: "#e0e0ff",
  },
  lockBadge: {
    fontSize: 11,
    color: "#43b581",
    fontWeight: "600",
  },
  empty: {
    color: "#888",
    textAlign: "center",
    marginTop: 40,
    fontSize: 15,
  },
});
