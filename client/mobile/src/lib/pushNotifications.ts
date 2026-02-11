/**
 * Push notification registration and handling.
 * Uses Expo Push service for cross-platform delivery.
 */

import * as Notifications from "expo-notifications";
import { Platform } from "react-native";
import { pushTokensApi } from "@murmuring/proto";
import { client } from "../api/client";

// Configure how notifications appear when app is in foreground
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

let pushToken: string | null = null;

/**
 * Request push notification permissions, get Expo push token,
 * and register it with the server.
 */
export async function registerForPushNotifications(): Promise<string | null> {
  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;

  if (existingStatus !== "granted") {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }

  if (finalStatus !== "granted") {
    console.log("Push notification permission denied");
    return null;
  }

  const tokenData = await Notifications.getExpoPushTokenAsync();
  pushToken = tokenData.data;

  // Register with server
  const platform = Platform.OS === "ios" ? "ios" : "android";
  try {
    await pushTokensApi.registerToken(client, pushToken, platform);
    console.log("Push token registered:", pushToken);
  } catch (err) {
    console.error("Failed to register push token:", err);
  }

  return pushToken;
}

/**
 * Unregister the push token from the server (called on logout).
 */
export async function unregisterPushNotifications(): Promise<void> {
  if (!pushToken) return;
  try {
    await pushTokensApi.unregisterToken(client, pushToken);
    pushToken = null;
  } catch (err) {
    console.error("Failed to unregister push token:", err);
  }
}

/**
 * Add a listener for notification responses (user taps notification).
 * Returns a cleanup function.
 */
export function addNotificationResponseListener(
  handler: (response: Notifications.NotificationResponse) => void,
): () => void {
  const subscription = Notifications.addNotificationResponseReceivedListener(handler);
  return () => subscription.remove();
}
