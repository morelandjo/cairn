import { useEffect } from "react";
import { View, StyleSheet } from "react-native";
import { useRouter } from "expo-router";
import { useServerStore } from "@/stores/serverStore";
import { ServerList } from "@/components/ServerList";

export default function ServersScreen() {
  const router = useRouter();
  const { servers, fetchServers, isLoadingServers } = useServerStore();

  useEffect(() => {
    fetchServers();
  }, [fetchServers]);

  const handleSelectServer = (serverId: string) => {
    router.push(`/(app)/(tabs)/servers/${serverId}`);
  };

  return (
    <View style={styles.container}>
      <ServerList
        servers={servers}
        isLoading={isLoadingServers}
        onSelectServer={handleSelectServer}
        onCreateServer={() => {
          // TODO: Create server modal
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
});
