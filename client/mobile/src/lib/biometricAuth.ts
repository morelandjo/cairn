/**
 * Biometric authentication using expo-local-authentication.
 * Provides Face ID / Touch ID / fingerprint lock for the app.
 */

import * as LocalAuthentication from "expo-local-authentication";

/** Check if biometric authentication is available on this device. */
export async function isBiometricAvailable(): Promise<boolean> {
  const compatible = await LocalAuthentication.hasHardwareAsync();
  if (!compatible) return false;
  const enrolled = await LocalAuthentication.isEnrolledAsync();
  return enrolled;
}

/** Get the types of biometric authentication available. */
export async function getBiometricTypes(): Promise<LocalAuthentication.AuthenticationType[]> {
  return LocalAuthentication.supportedAuthenticationTypesAsync();
}

/**
 * Prompt the user for biometric authentication.
 * Returns true if authentication succeeds, false otherwise.
 */
export async function authenticate(
  promptMessage = "Unlock Cairn",
): Promise<boolean> {
  const result = await LocalAuthentication.authenticateAsync({
    promptMessage,
    fallbackLabel: "Use Passcode",
    disableDeviceFallback: false,
  });
  return result.success;
}
