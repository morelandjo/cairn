/**
 * Search API — delegates to @cairn/proto.
 */

import { searchApi } from "@cairn/proto";
import { client } from "./client.ts";

export type { SearchResult } from "@cairn/proto/api";

export function searchMessages(
  serverId: string,
  query: string,
  channelId?: string,
) {
  return searchApi.searchMessages(client, serverId, query, channelId);
}
