/**
 * MLS API — delegates to @murmuring/proto.
 */

import { mlsApi } from "@murmuring/proto";
import { client } from "./client.ts";

export type { MlsProtocolMessage } from "@murmuring/proto/api";

// KeyPackage endpoints

export function uploadKeyPackages(packages: string[]) {
  return mlsApi.uploadKeyPackages(client, packages);
}

export function claimKeyPackage(userId: string) {
  return mlsApi.claimKeyPackage(client, userId);
}

export function keyPackageCount() {
  return mlsApi.keyPackageCount(client);
}

// MLS Group Info

export function storeGroupInfo(
  channelId: string,
  data: string,
  epoch: number,
) {
  return mlsApi.storeGroupInfo(client, channelId, data, epoch);
}

export function getGroupInfo(channelId: string) {
  return mlsApi.getGroupInfo(client, channelId);
}

// MLS Protocol Messages

export function storeCommit(
  channelId: string,
  data: string,
  epoch?: number,
) {
  return mlsApi.storeCommit(client, channelId, data, epoch);
}

export function storeProposal(
  channelId: string,
  data: string,
  epoch?: number,
) {
  return mlsApi.storeProposal(client, channelId, data, epoch);
}

export function storeWelcome(
  channelId: string,
  data: string,
  recipientId: string,
) {
  return mlsApi.storeWelcome(client, channelId, data, recipientId);
}

export function getPendingMessages(channelId: string) {
  return mlsApi.getPendingMessages(client, channelId);
}

export function ackMessages(channelId: string, messageIds: string[]) {
  return mlsApi.ackMessages(client, channelId, messageIds);
}
