/**
 * Webhooks & Bots API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface Webhook {
  id: string;
  name: string;
  token?: string;
  channel_id: string;
  avatar_key: string | null;
}

export interface BotAccount {
  id: string;
  user_id: string;
  username: string;
  token?: string;
  allowed_channels?: string[];
  inserted_at?: string;
}

// Webhooks

export function listWebhooks(
  client: ApiClient,
  serverId: string,
): Promise<{ webhooks: Webhook[] }> {
  return client.fetch<{ webhooks: Webhook[] }>(
    `/api/v1/servers/${serverId}/webhooks`,
  );
}

export function createWebhook(
  client: ApiClient,
  serverId: string,
  params: { name: string; channel_id: string },
): Promise<{ webhook: Webhook }> {
  return client.fetch<{ webhook: Webhook }>(
    `/api/v1/servers/${serverId}/webhooks`,
    { method: "POST", body: JSON.stringify(params) },
  );
}

export function deleteWebhook(
  client: ApiClient,
  serverId: string,
  webhookId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/webhooks/${webhookId}`,
    { method: "DELETE" },
  );
}

export function regenerateWebhookToken(
  client: ApiClient,
  serverId: string,
  webhookId: string,
): Promise<{ webhook: { id: string; token: string } }> {
  return client.fetch<{ webhook: { id: string; token: string } }>(
    `/api/v1/servers/${serverId}/webhooks/${webhookId}/regenerate-token`,
    { method: "POST" },
  );
}

// Bots

export function listBots(
  client: ApiClient,
  serverId: string,
): Promise<{ bots: BotAccount[] }> {
  return client.fetch<{ bots: BotAccount[] }>(
    `/api/v1/servers/${serverId}/bots`,
  );
}

export function createBot(
  client: ApiClient,
  serverId: string,
): Promise<{ bot: BotAccount }> {
  return client.fetch<{ bot: BotAccount }>(
    `/api/v1/servers/${serverId}/bots`,
    { method: "POST" },
  );
}

export function deleteBot(
  client: ApiClient,
  serverId: string,
  botId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/bots/${botId}`,
    { method: "DELETE" },
  );
}

export function updateBotChannels(
  client: ApiClient,
  serverId: string,
  botId: string,
  channels: string[],
): Promise<{ bot: { id: string; allowed_channels: string[] } }> {
  return client.fetch<{ bot: { id: string; allowed_channels: string[] } }>(
    `/api/v1/servers/${serverId}/bots/${botId}/channels`,
    { method: "PUT", body: JSON.stringify({ channels }) },
  );
}

export function regenerateBotToken(
  client: ApiClient,
  serverId: string,
  botId: string,
): Promise<{ token: string }> {
  return client.fetch<{ token: string }>(
    `/api/v1/servers/${serverId}/bots/${botId}/regenerate-token`,
    { method: "POST" },
  );
}
