import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import type { Server } from "../api/servers";

interface Props {
  servers: Server[];
  isLoading: boolean;
  onSelectServer: (serverId: string) => void;
  onCreateServer: () => void;
}

export function ServerList({ servers, isLoading, onSelectServer, onCreateServer }: Props) {
  if (isLoading) {
    return <ActivityIndicator color="#5865f2" style={styles.loader} />;
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Servers</Text>
        <TouchableOpacity onPress={onCreateServer}>
          <Text style={styles.addButton}>+</Text>
        </TouchableOpacity>
      </View>
      <FlatList
        data={servers}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <TouchableOpacity
            style={styles.item}
            onPress={() => onSelectServer(item.id)}
          >
            <View style={styles.serverIcon}>
              <Text style={styles.serverIconText}>
                {item.name[0].toUpperCase()}
              </Text>
            </View>
            <View style={styles.serverInfo}>
              <Text style={styles.serverName}>{item.name}</Text>
              {item.description && (
                <Text style={styles.serverDesc} numberOfLines={1}>
                  {item.description}
                </Text>
              )}
            </View>
          </TouchableOpacity>
        )}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>No servers yet</Text>
            <TouchableOpacity style={styles.createButton} onPress={onCreateServer}>
              <Text style={styles.createButtonText}>Create a Server</Text>
            </TouchableOpacity>
          </View>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
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
  addButton: {
    color: "#5865f2",
    fontSize: 28,
    fontWeight: "bold",
  },
  loader: {
    marginTop: 40,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: "#252540",
  },
  serverIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: "#5865f2",
    justifyContent: "center",
    alignItems: "center",
    marginRight: 12,
  },
  serverIconText: {
    color: "#fff",
    fontWeight: "bold",
    fontSize: 18,
  },
  serverInfo: {
    flex: 1,
  },
  serverName: {
    color: "#e0e0ff",
    fontSize: 16,
    fontWeight: "600",
  },
  serverDesc: {
    color: "#888",
    fontSize: 13,
    marginTop: 2,
  },
  emptyContainer: {
    alignItems: "center",
    marginTop: 60,
  },
  emptyText: {
    color: "#888",
    fontSize: 16,
    marginBottom: 16,
  },
  createButton: {
    backgroundColor: "#5865f2",
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 24,
  },
  createButtonText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 15,
  },
});
