/**
 * Push token API — delegates to @cairn/proto.
 */

import { pushTokensApi } from "@cairn/proto";
import { client } from "./client";

export type { PushTokenResponse } from "@cairn/proto/api";

export function registerToken(token: string, platform: string, deviceId?: string) {
  return pushTokensApi.registerToken(client, token, platform, deviceId);
}

export function unregisterToken(token: string) {
  return pushTokensApi.unregisterToken(client, token);
}
