/**
 * Voice/Video configuration — delegates to @murmuring/proto.
 */

import { voiceApi } from "@murmuring/proto";
import { client } from "./client";

export type { IceServerConfig } from "@murmuring/proto/api";

export function getIceServers() {
  return voiceApi.getIceServers(client);
}

export function getTurnCredentials() {
  return voiceApi.getTurnCredentials(client);
}
