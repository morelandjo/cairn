/**
 * Server connection screen — mobile first launch.
 * Enter server URL manually or scan QR code.
 */

import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  FlatList,
  Alert,
} from "react-native";
import { setServerUrl } from "../lib/config";

interface ServerConnectProps {
  onConnect: () => void;
}

export default function ServerConnect({ onConnect }: ServerConnectProps) {
  const [url, setUrl] = useState("");
  const [checking, setChecking] = useState(false);
  const [recentServers] = useState<string[]>(() => {
    // In a real app, load from AsyncStorage
    return [];
  });

  async function handleConnect() {
    let serverUrl = url.trim().replace(/\/$/, "");
    if (!serverUrl.startsWith("http")) {
      serverUrl = `https://${serverUrl}`;
    }

    setChecking(true);
    try {
      const resp = await fetch(`${serverUrl}/health`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) throw new Error("Server error");

      // Warn if connecting over plain HTTP
      if (serverUrl.startsWith("http://")) {
        setChecking(false);
        Alert.alert(
          "Insecure Connection",
          "This server does not use an encrypted connection. Your messages, credentials, and other data could be intercepted by third parties. This is only safe on trusted private networks (e.g. home LAN, Tailscale).",
          [
            { text: "Cancel", style: "cancel" },
            {
              text: "Continue Anyway",
              style: "destructive",
              onPress: () => {
                setServerUrl(serverUrl);
                onConnect();
              },
            },
          ],
        );
        return;
      }

      setServerUrl(serverUrl);
      onConnect();
    } catch {
      Alert.alert("Connection Failed", "Could not connect to server. Check the URL and try again.");
    } finally {
      setChecking(false);
    }
  }

  function handleSelectRecent(serverUrl: string) {
    setServerUrl(serverUrl);
    onConnect();
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Cairn</Text>
      <Text style={styles.subtitle}>Connect to a server</Text>

      <TextInput
        style={styles.input}
        placeholder="cairn.example.com"
        placeholderTextColor="#666"
        value={url}
        onChangeText={setUrl}
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="url"
        returnKeyType="go"
        onSubmitEditing={handleConnect}
      />

      <TouchableOpacity
        style={[styles.button, (!url.trim() || checking) && styles.buttonDisabled]}
        onPress={handleConnect}
        disabled={!url.trim() || checking}
      >
        {checking ? (
          <ActivityIndicator color="#fff" />
        ) : (
          <Text style={styles.buttonText}>Connect</Text>
        )}
      </TouchableOpacity>

      {recentServers.length > 0 && (
        <View style={styles.recentSection}>
          <Text style={styles.recentTitle}>Recent servers</Text>
          <FlatList
            data={recentServers}
            keyExtractor={(item) => item}
            renderItem={({ item }) => (
              <TouchableOpacity
                style={styles.recentItem}
                onPress={() => handleSelectRecent(item)}
              >
                <Text style={styles.recentText}>
                  {item.replace(/^https?:\/\//, "")}
                </Text>
              </TouchableOpacity>
            )}
          />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: "center",
    padding: 32,
    backgroundColor: "#1a1a2e",
  },
  title: {
    fontSize: 28,
    fontWeight: "bold",
    color: "#e0e0e0",
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: "#888",
    marginBottom: 32,
  },
  input: {
    padding: 14,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#333",
    backgroundColor: "#0f3460",
    color: "#fff",
    fontSize: 16,
  },
  button: {
    padding: 14,
    borderRadius: 8,
    backgroundColor: "#533483",
    alignItems: "center",
    marginTop: 16,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  recentSection: {
    marginTop: 32,
  },
  recentTitle: {
    color: "#888",
    fontSize: 14,
    marginBottom: 8,
  },
  recentItem: {
    padding: 10,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#333",
    marginBottom: 4,
  },
  recentText: {
    color: "#aaa",
    fontSize: 14,
  },
});
