/**
 * Search API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface SearchResult {
  id: string;
  content: string;
  author_id: string;
  author_username: string;
  channel_id: string;
  channel_name: string;
  inserted_at: string;
}

export function searchMessages(
  client: ApiClient,
  serverId: string,
  query: string,
  channelId?: string,
): Promise<{ results: SearchResult[] }> {
  const params = new URLSearchParams({ q: query });
  if (channelId) {
    params.set("channel_id", channelId);
  }
  return client.fetch<{ results: SearchResult[] }>(
    `/api/v1/servers/${serverId}/search?${params.toString()}`,
  );
}
