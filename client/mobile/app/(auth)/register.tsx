import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Alert,
} from "react-native";
import { useRouter, Link } from "expo-router";
import { useAuthStore } from "@/stores/authStore";

export default function RegisterScreen() {
  const router = useRouter();
  const { register, isLoading, error, setError, recoveryCodes, clearRecoveryCodes } = useAuthStore();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");

  const handleRegister = async () => {
    if (!username.trim() || !password) return;
    setError(null);
    try {
      await register(username.trim(), password, displayName.trim() || undefined);
    } catch {
      // error is set in store
    }
  };

  const handleDismissRecoveryCodes = () => {
    Alert.alert(
      "Save Recovery Codes",
      "Make sure you have saved your recovery codes. You will need them if you lose access to your account.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "I've Saved Them",
          onPress: () => {
            clearRecoveryCodes();
            router.replace("/(app)/(tabs)/servers");
          },
        },
      ],
    );
  };

  if (recoveryCodes) {
    return (
      <View style={styles.container}>
        <View style={styles.inner}>
          <Text style={styles.title}>Recovery Codes</Text>
          <Text style={styles.subtitle}>
            Save these codes somewhere safe. You'll need them if you lose access to your account.
          </Text>
          <View style={styles.codesBox}>
            {recoveryCodes.map((code, i) => (
              <Text key={i} style={styles.code}>{code}</Text>
            ))}
          </View>
          <TouchableOpacity style={styles.button} onPress={handleDismissRecoveryCodes}>
            <Text style={styles.buttonText}>Continue</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === "ios" ? "padding" : "height"}
    >
      <View style={styles.inner}>
        <Text style={styles.title}>Create Account</Text>
        <Text style={styles.subtitle}>Join Murmuring</Text>

        {error && <Text style={styles.error}>{error}</Text>}

        <TextInput
          style={styles.input}
          placeholder="Username"
          placeholderTextColor="#888"
          autoCapitalize="none"
          autoCorrect={false}
          value={username}
          onChangeText={setUsername}
        />

        <TextInput
          style={styles.input}
          placeholder="Display Name (optional)"
          placeholderTextColor="#888"
          value={displayName}
          onChangeText={setDisplayName}
        />

        <TextInput
          style={styles.input}
          placeholder="Password"
          placeholderTextColor="#888"
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          onSubmitEditing={handleRegister}
        />

        <TouchableOpacity
          style={[styles.button, isLoading && styles.buttonDisabled]}
          onPress={handleRegister}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Create Account</Text>
          )}
        </TouchableOpacity>

        <Link href="/(auth)/login" style={styles.link}>
          <Text style={styles.linkText}>Already have an account? Sign in</Text>
        </Link>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1a1a2e",
  },
  inner: {
    flex: 1,
    justifyContent: "center",
    paddingHorizontal: 32,
  },
  title: {
    fontSize: 32,
    fontWeight: "bold",
    color: "#e0e0ff",
    textAlign: "center",
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: "#888",
    textAlign: "center",
    marginBottom: 32,
  },
  error: {
    color: "#ff6b6b",
    textAlign: "center",
    marginBottom: 16,
    fontSize: 14,
  },
  input: {
    backgroundColor: "#252540",
    borderRadius: 8,
    padding: 14,
    fontSize: 16,
    color: "#e0e0ff",
    marginBottom: 12,
    borderWidth: 1,
    borderColor: "#333355",
  },
  button: {
    backgroundColor: "#5865f2",
    borderRadius: 8,
    padding: 14,
    alignItems: "center",
    marginTop: 8,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  link: {
    marginTop: 20,
    alignSelf: "center",
  },
  linkText: {
    color: "#5865f2",
    fontSize: 14,
  },
  codesBox: {
    backgroundColor: "#252540",
    borderRadius: 8,
    padding: 16,
    marginBottom: 24,
  },
  code: {
    color: "#e0e0ff",
    fontFamily: Platform.OS === "ios" ? "Menlo" : "monospace",
    fontSize: 14,
    marginVertical: 2,
    textAlign: "center",
  },
});
