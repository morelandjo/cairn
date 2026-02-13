import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import type { Channel } from "../api/channels";

interface Props {
  channels: Channel[];
  isLoading: boolean;
  onSelectChannel: (channelId: string) => void;
}

function channelIcon(type?: string): string {
  switch (type) {
    case "voice":
      return "V";
    case "private":
      return "L";
    default:
      return "#";
  }
}

export function ChannelList({ channels, isLoading, onSelectChannel }: Props) {
  if (isLoading) {
    return <ActivityIndicator color="#5865f2" style={styles.loader} />;
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Channels</Text>
      </View>
      <FlatList
        data={channels}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <TouchableOpacity
            style={styles.item}
            onPress={() => onSelectChannel(item.id)}
          >
            <Text style={styles.icon}>{channelIcon(item.type)}</Text>
            <Text style={styles.name}>{item.name}</Text>
          </TouchableOpacity>
        )}
        ListEmptyComponent={
          <Text style={styles.empty}>No channels</Text>
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
  icon: {
    color: "#888",
    fontSize: 16,
    fontWeight: "bold",
    width: 24,
  },
  name: {
    color: "#e0e0ff",
    fontSize: 16,
    flex: 1,
  },
  empty: {
    color: "#888",
    textAlign: "center",
    marginTop: 40,
    fontSize: 15,
  },
});
