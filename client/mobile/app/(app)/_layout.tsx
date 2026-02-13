import { Redirect, Stack } from "expo-router";
import { useAuthStore } from "@/stores/authStore";

export default function AppLayout() {
  const user = useAuthStore((s) => s.user);

  if (!user) {
    return <Redirect href="/(auth)/login" />;
  }

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="invite/[code]" options={{ presentation: "modal" }} />
      <Stack.Screen name="discover" options={{ presentation: "modal" }} />
    </Stack>
  );
}
