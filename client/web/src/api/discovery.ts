/**
 * Server Discovery — delegates to @murmuring/proto.
 */

import { discoveryApi } from "@murmuring/proto";
import { client } from "./client.ts";

export type { DirectoryEntry } from "@murmuring/proto/api";

export function listDirectory(opts?: {
  limit?: number;
  offset?: number;
  tag?: string;
}) {
  return discoveryApi.listDirectory(client, opts);
}

export function listServer(
  serverId: string,
  params: { description?: string; tags?: string[] },
) {
  return discoveryApi.listServer(client, serverId, params);
}

export function unlistServer(serverId: string) {
  return discoveryApi.unlistServer(client, serverId);
}
