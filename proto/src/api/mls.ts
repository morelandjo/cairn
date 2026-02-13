/**
 * MLS API endpoints — KeyPackages + MLS delivery service.
 */

import type { ApiClient } from "./client.js";

// ==================== KeyPackage Endpoints ====================

export function uploadKeyPackages(
  client: ApiClient,
  packages: string[],
): Promise<{ count: number }> {
  return client.fetch<{ count: number }>("/api/v1/users/me/key-packages", {
    method: "POST",
    body: JSON.stringify({ key_packages: packages }),
  });
}

export function claimKeyPackage(
  client: ApiClient,
  userId: string,
): Promise<{ key_package: string | null }> {
  return client.fetch<{ key_package: string | null }>(
    `/api/v1/users/${userId}/key-packages`,
  );
}

export function keyPackageCount(
  client: ApiClient,
): Promise<{ count: number }> {
  return client.fetch<{ count: number }>("/api/v1/users/me/key-packages/count");
}

// ==================== MLS Group Info ====================

export function storeGroupInfo(
  client: ApiClient,
  channelId: string,
  data: string,
  epoch: number,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/channels/${channelId}/mls/group-info`,
    {
      method: "POST",
      body: JSON.stringify({ data, epoch }),
    },
  );
}

export function getGroupInfo(
  client: ApiClient,
  channelId: string,
): Promise<{ data: string; epoch: number }> {
  return client.fetch<{ data: string; epoch: number }>(
    `/api/v1/channels/${channelId}/mls/group-info`,
  );
}

// ==================== MLS Protocol Messages ====================

export interface MlsProtocolMessage {
  id: string;
  message_type: string;
  data: string;
  epoch: number | null;
  sender_id: string;
  inserted_at: string;
}

export function storeCommit(
  client: ApiClient,
  channelId: string,
  data: string,
  epoch?: number,
): Promise<{ id: string }> {
  return client.fetch<{ id: string }>(
    `/api/v1/channels/${channelId}/mls/commit`,
    {
      method: "POST",
      body: JSON.stringify({ data, epoch }),
    },
  );
}

export function storeProposal(
  client: ApiClient,
  channelId: string,
  data: string,
  epoch?: number,
): Promise<{ id: string }> {
  return client.fetch<{ id: string }>(
    `/api/v1/channels/${channelId}/mls/proposal`,
    {
      method: "POST",
      body: JSON.stringify({ data, epoch }),
    },
  );
}

export function storeWelcome(
  client: ApiClient,
  channelId: string,
  data: string,
  recipientId: string,
): Promise<{ id: string }> {
  return client.fetch<{ id: string }>(
    `/api/v1/channels/${channelId}/mls/welcome`,
    {
      method: "POST",
      body: JSON.stringify({ data, recipient_id: recipientId }),
    },
  );
}

export function getPendingMessages(
  client: ApiClient,
  channelId: string,
): Promise<{ messages: MlsProtocolMessage[] }> {
  return client.fetch<{ messages: MlsProtocolMessage[] }>(
    `/api/v1/channels/${channelId}/mls/messages`,
  );
}

export function ackMessages(
  client: ApiClient,
  channelId: string,
  messageIds: string[],
): Promise<{ acknowledged: number }> {
  return client.fetch<{ acknowledged: number }>(
    `/api/v1/channels/${channelId}/mls/ack`,
    {
      method: "POST",
      body: JSON.stringify({ message_ids: messageIds }),
    },
  );
}
