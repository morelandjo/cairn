/**
 * Voice/Video configuration API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface IceServerConfig {
  urls: string[];
  username?: string;
  credential?: string;
}

export async function getIceServers(
  client: ApiClient,
): Promise<IceServerConfig[]> {
  const res = await client.fetch<{ iceServers: IceServerConfig[] }>(
    "/api/v1/voice/ice-servers",
  );
  return res.iceServers;
}

export async function getTurnCredentials(
  client: ApiClient,
): Promise<IceServerConfig[]> {
  const res = await client.fetch<{ iceServers: IceServerConfig[] }>(
    "/api/v1/voice/turn-credentials",
  );
  return res.iceServers;
}
