import { useEffect, useState } from "react";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useAuthStore } from "@/stores/authStore";

export default function RootLayout() {
  const [ready, setReady] = useState(false);
  const loadSession = useAuthStore((s) => s.loadSession);

  useEffect(() => {
    loadSession().finally(() => setReady(true));
  }, [loadSession]);

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
