import { useEffect, useState } from "react";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useAuthStore } from "@/stores/authStore";
import { hasServerUrl, getApiBaseUrl } from "@/lib/config";
import { client } from "@/api/client";
import ServerConnect from "@/components/ServerConnect";

export default function RootLayout() {
  const [serverReady, setServerReady] = useState(hasServerUrl());
  const [ready, setReady] = useState(false);
  const loadSession = useAuthStore((s) => s.loadSession);

  function handleConnect() {
    client.configure({ baseUrl: getApiBaseUrl() });
    setServerReady(true);
  }

  useEffect(() => {
    if (!serverReady) return;
    loadSession().finally(() => setReady(true));
  }, [loadSession, serverReady]);

  if (!serverReady) {
    return (
      <>
        <StatusBar style="light" />
        <ServerConnect onConnect={handleConnect} />
      </>
    );
  }

  if (!ready) return null;

  return (
    <>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(auth)" />
        <Stack.Screen name="(app)" />
      </Stack>
    </>
  );
}
