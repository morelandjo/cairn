/**
 * Search API — delegates to @murmuring/proto.
 */

import { searchApi } from "@murmuring/proto";
import { client } from "./client";

export type { SearchResult } from "@murmuring/proto/api";

export function searchMessages(
  serverId: string,
  query: string,
  channelId?: string,
) {
  return searchApi.searchMessages(client, serverId, query, channelId);
}
