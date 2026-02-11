/**
 * Server Discovery API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface DirectoryEntry {
  id: string;
  server_id: string;
  server_name: string;
  description: string | null;
  tags: string[];
  member_count: number;
  listed_at: string;
}

export function listDirectory(
  client: ApiClient,
  opts?: { limit?: number; offset?: number; tag?: string },
): Promise<{ servers: DirectoryEntry[] }> {
  const params = new URLSearchParams();
  if (opts?.limit) params.set("limit", String(opts.limit));
  if (opts?.offset) params.set("offset", String(opts.offset));
  if (opts?.tag) params.set("tag", opts.tag);
  const qs = params.toString();
  return client.fetch<{ servers: DirectoryEntry[] }>(
    `/api/v1/directory${qs ? `?${qs}` : ""}`,
  );
}

export function listServer(
  client: ApiClient,
  serverId: string,
  params: { description?: string; tags?: string[] },
): Promise<{ entry: DirectoryEntry }> {
  return client.fetch<{ entry: DirectoryEntry }>(
    `/api/v1/servers/${serverId}/directory/list`,
    { method: "POST", body: JSON.stringify(params) },
  );
}

export function unlistServer(
  client: ApiClient,
  serverId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/directory/unlist`,
    { method: "DELETE" },
  );
}
