/**
 * Voice/Video configuration — delegates to @cairn/proto.
 */

import { voiceApi } from "@cairn/proto";
import { client } from "./client";

export type { IceServerConfig } from "@cairn/proto/api";

export function getIceServers() {
  return voiceApi.getIceServers(client);
}

export function getTurnCredentials() {
  return voiceApi.getTurnCredentials(client);
}
