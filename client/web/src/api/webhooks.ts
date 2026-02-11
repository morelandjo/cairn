/**
 * Webhooks & Bots — delegates to @murmuring/proto.
 */

import { webhooksApi } from "@murmuring/proto";
import { client } from "./client.ts";

export type { Webhook, BotAccount } from "@murmuring/proto/api";

// Webhooks

export function listWebhooks(serverId: string) {
  return webhooksApi.listWebhooks(client, serverId);
}

export function createWebhook(
  serverId: string,
  params: { name: string; channel_id: string },
) {
  return webhooksApi.createWebhook(client, serverId, params);
}

export function deleteWebhook(serverId: string, webhookId: string) {
  return webhooksApi.deleteWebhook(client, serverId, webhookId);
}

export function regenerateWebhookToken(serverId: string, webhookId: string) {
  return webhooksApi.regenerateWebhookToken(client, serverId, webhookId);
}

// Bots

export function listBots(serverId: string) {
  return webhooksApi.listBots(client, serverId);
}

export function createBot(serverId: string) {
  return webhooksApi.createBot(client, serverId);
}

export function deleteBot(serverId: string, botId: string) {
  return webhooksApi.deleteBot(client, serverId, botId);
}

export function updateBotChannels(
  serverId: string,
  botId: string,
  channels: string[],
) {
  return webhooksApi.updateBotChannels(client, serverId, botId, channels);
}

export function regenerateBotToken(serverId: string, botId: string) {
  return webhooksApi.regenerateBotToken(client, serverId, botId);
}
