/**
 * Channels API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface Channel {
  id: string;
  name: string;
  type: string;
  description: string | null;
  history_accessible?: boolean;
  inserted_at: string;
}

export interface Reaction {
  emoji: string;
  count: number;
}

export interface ReplyToSummary {
  id: string;
  author_username: string;
  content_snippet: string | null;
}

export interface Message {
  id: string;
  content: string | null;
  encrypted_content?: string | null;
  nonce?: string | null;
  author_id: string;
  author_username: string;
  author_display_name: string | null;
  is_bot?: boolean;
  is_federated?: boolean;
  home_instance?: string | null;
  federated_author_id?: string | null;
  channel_id: string;
  edited_at?: string | null;
  deleted_at?: string | null;
  reply_to_id?: string | null;
  reply_to?: ReplyToSummary | null;
  reactions?: Reaction[];
  inserted_at: string;
}

export interface Member {
  id: string;
  username: string;
  display_name: string | null;
}

export function listChannels(
  client: ApiClient,
): Promise<{ channels: Channel[] }> {
  return client.fetch<{ channels: Channel[] }>("/api/v1/channels");
}

export function createChannel(
  client: ApiClient,
  params: {
    name: string;
    type?: string;
    description?: string;
    history_accessible?: boolean;
  },
): Promise<{ channel: Channel }> {
  return client.fetch<{ channel: Channel }>("/api/v1/channels", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function getMessages(
  client: ApiClient,
  channelId: string,
  opts?: { limit?: number; before?: string },
): Promise<{ messages: Message[] }> {
  const params = new URLSearchParams();
  if (opts?.limit) params.set("limit", String(opts.limit));
  if (opts?.before) params.set("before", opts.before);
  const qs = params.toString();
  const path = `/api/v1/channels/${channelId}/messages${qs ? `?${qs}` : ""}`;
  return client.fetch<{ messages: Message[] }>(path);
}

export function getMembers(
  client: ApiClient,
  channelId: string,
): Promise<{ members: Member[] }> {
  return client.fetch<{ members: Member[] }>(
    `/api/v1/channels/${channelId}/members`,
  );
}

// Reactions

export function addReaction(
  client: ApiClient,
  channelId: string,
  messageId: string,
  emoji: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/channels/${channelId}/messages/${messageId}/reactions`,
    { method: "POST", body: JSON.stringify({ emoji }) },
  );
}

export function removeReaction(
  client: ApiClient,
  channelId: string,
  messageId: string,
  emoji: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/channels/${channelId}/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`,
    { method: "DELETE" },
  );
}

export function getReactions(
  client: ApiClient,
  channelId: string,
  messageId: string,
): Promise<{
  reactions: Array<{ emoji: string; user_id: string; username: string }>;
}> {
  return client.fetch<{
    reactions: Array<{ emoji: string; user_id: string; username: string }>;
  }>(`/api/v1/channels/${channelId}/messages/${messageId}/reactions`);
}

// Threads

export function getThread(
  client: ApiClient,
  channelId: string,
  messageId: string,
): Promise<{ parent: Message; replies: Message[] }> {
  return client.fetch<{ parent: Message; replies: Message[] }>(
    `/api/v1/channels/${channelId}/messages/${messageId}/thread`,
  );
}

// Pins

export function listPins(
  client: ApiClient,
  channelId: string,
): Promise<{
  pins: Array<{
    id: string;
    message_id: string;
    pinned_by_id: string;
    inserted_at: string;
    message: Message;
  }>;
}> {
  return client.fetch<{
    pins: Array<{
      id: string;
      message_id: string;
      pinned_by_id: string;
      inserted_at: string;
      message: Message;
    }>;
  }>(`/api/v1/channels/${channelId}/pins`);
}

export function pinMessage(
  client: ApiClient,
  channelId: string,
  messageId: string,
): Promise<{ pin: { id: string } }> {
  return client.fetch<{ pin: { id: string } }>(
    `/api/v1/channels/${channelId}/pins`,
    { method: "POST", body: JSON.stringify({ message_id: messageId }) },
  );
}

export function unpinMessage(
  client: ApiClient,
  channelId: string,
  messageId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/channels/${channelId}/pins/${messageId}`,
    { method: "DELETE" },
  );
}
