/**
 * MLS API — delegates to @cairn/proto.
 * Note: MLS WASM not supported on mobile (Hermes), but API calls still work
 * for compatibility. Private channels show warning instead.
 */

import { mlsApi } from "@cairn/proto";
import { client } from "./client";

export type { MlsProtocolMessage } from "@cairn/proto/api";

export function uploadKeyPackages(packages: string[]) {
  return mlsApi.uploadKeyPackages(client, packages);
}

export function claimKeyPackage(userId: string) {
  return mlsApi.claimKeyPackage(client, userId);
}

export function keyPackageCount() {
  return mlsApi.keyPackageCount(client);
}

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
