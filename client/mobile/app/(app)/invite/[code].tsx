import { useEffect, useState } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import * as invitesApi from "@/api/invites";

export default function InviteScreen() {
  const { code } = useLocalSearchParams<{ code: string }>();
  const router = useRouter();
  const [invite, setInvite] = useState<invitesApi.InviteInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isJoining, setIsJoining] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!code) return;
    invitesApi
      .getInvite(code)
      .then((data) => setInvite(data.invite))
      .catch(() => setError("Invalid invite"))
      .finally(() => setIsLoading(false));
  }, [code]);

  const handleJoin = async () => {
    if (!code) return;
    setIsJoining(true);
    try {
      await invitesApi.useInvite(code);
      router.replace("/(app)/(tabs)/servers");
    } catch {
      setError("Failed to join");
    } finally {
      setIsJoining(false);
    }
  };

  if (isLoading) {
    return (
      <View style={styles.container}>
        <ActivityIndicator color="#5865f2" />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.card}>
        {error ? (
          <Text style={styles.error}>{error}</Text>
        ) : (
          <>
            <Text style={styles.title}>You've been invited!</Text>
            <Text style={styles.info}>
              {(invite as Record<string, unknown>)?.server_name as string ?? "Server"}
            </Text>
          </>
        )}

        <TouchableOpacity
          style={[styles.button, (isJoining || !!error) && styles.buttonDisabled]}
          onPress={handleJoin}
          disabled={isJoining || !!error}
        >
          {isJoining ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Accept Invite</Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity onPress={() => router.back()} style={styles.cancelButton}>
          <Text style={styles.cancelText}>Cancel</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
    justifyContent: "center",
    alignItems: "center",
    padding: 32,
  },
  card: {
    backgroundColor: "#252540",
    borderRadius: 12,
    padding: 32,
    width: "100%",
    alignItems: "center",
  },
  title: {
    fontSize: 22,
    fontWeight: "bold",
    color: "#e0e0ff",
    marginBottom: 8,
  },
  info: {
    fontSize: 16,
    color: "#888",
    marginBottom: 24,
  },
  error: {
    fontSize: 16,
    color: "#ff6b6b",
    marginBottom: 24,
  },
  button: {
    backgroundColor: "#5865f2",
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 48,
    alignItems: "center",
    width: "100%",
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  cancelButton: {
    marginTop: 16,
  },
  cancelText: {
    color: "#888",
    fontSize: 14,
  },
});
