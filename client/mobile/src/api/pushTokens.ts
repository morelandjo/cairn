/**
 * Push token API — delegates to @murmuring/proto.
 */

import { pushTokensApi } from "@murmuring/proto";
import { client } from "./client";

export type { PushTokenResponse } from "@murmuring/proto/api";

export function registerToken(token: string, platform: string, deviceId?: string) {
  return pushTokensApi.registerToken(client, token, platform, deviceId);
}

export function unregisterToken(token: string) {
  return pushTokensApi.unregisterToken(client, token);
}
