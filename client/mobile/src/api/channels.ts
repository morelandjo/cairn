/**
 * Channels API endpoints — delegates to @murmuring/proto.
 */

import { channelsApi } from "@murmuring/proto";
import { client } from "./client";

export type {
  Channel,
  Reaction,
  ReplyToSummary,
  Message,
  Member,
} from "@murmuring/proto/api";

export function listChannels() {
  return channelsApi.listChannels(client);
}

export function createChannel(params: {
  name: string;
  type?: string;
  description?: string;
}) {
  return channelsApi.createChannel(client, params);
}

export function getMessages(
  channelId: string,
  opts?: { limit?: number; before?: string },
) {
  return channelsApi.getMessages(client, channelId, opts);
}

export function getMembers(channelId: string) {
  return channelsApi.getMembers(client, channelId);
}

export function addReaction(
  channelId: string,
  messageId: string,
  emoji: string,
) {
  return channelsApi.addReaction(client, channelId, messageId, emoji);
}

export function removeReaction(
  channelId: string,
  messageId: string,
  emoji: string,
) {
  return channelsApi.removeReaction(client, channelId, messageId, emoji);
}

export function getReactions(channelId: string, messageId: string) {
  return channelsApi.getReactions(client, channelId, messageId);
}

export function getThread(channelId: string, messageId: string) {
  return channelsApi.getThread(client, channelId, messageId);
}

export function listPins(channelId: string) {
  return channelsApi.listPins(client, channelId);
}

export function pinMessage(channelId: string, messageId: string) {
  return channelsApi.pinMessage(client, channelId, messageId);
}

export function unpinMessage(channelId: string, messageId: string) {
  return channelsApi.unpinMessage(client, channelId, messageId);
}
