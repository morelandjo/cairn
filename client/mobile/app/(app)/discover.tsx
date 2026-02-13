import { useEffect, useState } from "react";
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import { useRouter } from "expo-router";
import * as discoveryApi from "@/api/discovery";
import type { DirectoryEntry } from "@/api/discovery";
import * as serversApi from "@/api/servers";

export default function DiscoverScreen() {
  const router = useRouter();
  const [entries, setEntries] = useState<DirectoryEntry[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    discoveryApi
      .listDirectory({ limit: 50 })
      .then((data) => setEntries(data.servers))
      .catch((err) => console.error("Failed to load directory:", err))
      .finally(() => setIsLoading(false));
  }, []);

  const handleJoin = async (serverId: string) => {
    try {
      await serversApi.joinServer(serverId);
      router.replace("/(app)/(tabs)/servers");
    } catch (err) {
      console.error("Failed to join server:", err);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Text style={styles.backText}>{"<"}</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Discover Servers</Text>
      </View>

      {isLoading ? (
        <ActivityIndicator color="#5865f2" style={styles.loader} />
      ) : (
        <FlatList
          data={entries}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <View style={styles.entry}>
              <View style={styles.entryInfo}>
                <Text style={styles.entryName}>{item.server_name}</Text>
                <Text style={styles.entryDesc} numberOfLines={2}>
                  {item.description ?? ""}
                </Text>
              </View>
              <TouchableOpacity
                style={styles.joinButton}
                onPress={() => handleJoin(item.server_id)}
              >
                <Text style={styles.joinText}>Join</Text>
              </TouchableOpacity>
            </View>
          )}
          ListEmptyComponent={
            <Text style={styles.empty}>No servers listed yet</Text>
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
    fontSize: 18,
    fontWeight: "600",
    color: "#e0e0ff",
  },
  loader: {
    marginTop: 40,
  },
  entry: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: "#252540",
  },
  entryInfo: {
    flex: 1,
  },
  entryName: {
    fontSize: 16,
    fontWeight: "600",
    color: "#e0e0ff",
    marginBottom: 2,
  },
  entryDesc: {
    fontSize: 13,
    color: "#888",
  },
  joinButton: {
    backgroundColor: "#5865f2",
    borderRadius: 6,
    paddingVertical: 8,
    paddingHorizontal: 16,
    marginLeft: 12,
  },
  joinText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  empty: {
    color: "#888",
    textAlign: "center",
    marginTop: 40,
    fontSize: 15,
  },
});
