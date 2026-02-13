import { View, Text, FlatList, StyleSheet } from "react-native";
import type { Member } from "../api/channels";
import { usePresenceStore } from "../stores/presenceStore";

interface Props {
  members: Member[];
}

export function MemberList({ members }: Props) {
  const isOnline = usePresenceStore((s) => s.isOnline);

  const online = members.filter((m) => isOnline(m.id));
  const offline = members.filter((m) => !isOnline(m.id));

  return (
    <FlatList
      data={[...online, ...offline]}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => {
        const isUserOnline = isOnline(item.id);
        return (
          <View style={styles.item}>
            <View style={[styles.dot, isUserOnline ? styles.dotOnline : styles.dotOffline]} />
            <Text style={[styles.name, !isUserOnline && styles.nameOffline]}>
              {item.display_name ?? item.username}
            </Text>
          </View>
        );
      }}
      ListHeaderComponent={
        <Text style={styles.header}>Members ({members.length})</Text>
      }
    />
  );
}

const styles = StyleSheet.create({
  header: {
    color: "#888",
    fontSize: 13,
    fontWeight: "600",
    textTransform: "uppercase",
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 10,
  },
  dotOnline: {
    backgroundColor: "#43b581",
  },
  dotOffline: {
    backgroundColor: "#666",
  },
  name: {
    color: "#e0e0ff",
    fontSize: 15,
  },
  nameOffline: {
    color: "#888",
  },
});
