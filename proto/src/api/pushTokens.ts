/**
 * Push notification token management API.
 */

import type { ApiClient } from "./client.js";

export interface PushTokenResponse {
  push_token: {
    id: string;
    token: string;
    platform: string;
    device_id?: string;
  };
}

export async function registerToken(
  client: ApiClient,
  token: string,
  platform: string,
  deviceId?: string,
): Promise<PushTokenResponse> {
  return client.fetch<PushTokenResponse>("/api/v1/users/me/push-tokens", {
    method: "POST",
    body: JSON.stringify({ token, platform, device_id: deviceId }),
  });
}

export async function unregisterToken(
  client: ApiClient,
  token: string,
): Promise<void> {
  await client.fetch<void>(
    `/api/v1/users/me/push-tokens/${encodeURIComponent(token)}`,
    { method: "DELETE" },
  );
}
