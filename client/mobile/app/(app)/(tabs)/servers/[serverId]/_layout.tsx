import { Stack, useLocalSearchParams } from "expo-router";
import { useEffect } from "react";
import { useServerStore } from "@/stores/serverStore";

export default function ServerLayout() {
  const { serverId } = useLocalSearchParams<{ serverId: string }>();
  const selectServer = useServerStore((s) => s.selectServer);

  useEffect(() => {
    if (serverId) {
      selectServer(serverId);
    }
  }, [serverId, selectServer]);

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="index" />
      <Stack.Screen name="[channelId]" />
    </Stack>
  );
}
