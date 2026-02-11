/**
 * Federation API endpoints for cross-instance operations.
 */

import type { ApiClient } from "./client.js";

export interface FederatedTokenResponse {
  token: string;
}

export interface JoinServerResponse {
  ok: boolean;
  server_id?: string;
  already_member?: boolean;
}

export interface FederatedChannel {
  id: string;
  name: string;
  type: string;
  position: number;
}

export interface ServerChannelsResponse {
  channels: FederatedChannel[];
}

/**
 * Request a federated auth token for authenticating with a remote instance.
 * Must be called on the user's home instance.
 */
export function requestFederatedToken(
  client: ApiClient,
  targetInstance: string,
): Promise<FederatedTokenResponse> {
  return client.fetch<FederatedTokenResponse>(
    "/api/v1/federation/auth-token",
    {
      method: "POST",
      body: JSON.stringify({ target_instance: targetInstance }),
    },
  );
}

/**
 * Join a server on a remote instance using a federated token.
 * Must be called on the remote instance's API client.
 */
export function joinServer(
  client: ApiClient,
  serverId: string,
): Promise<JoinServerResponse> {
  return client.fetch<JoinServerResponse>(
    `/api/v1/federated/join/${serverId}`,
    { method: "POST" },
  );
}

/**
 * List channels in a remote server using a federated token.
 */
export function getServerChannels(
  client: ApiClient,
  serverId: string,
): Promise<ServerChannelsResponse> {
  return client.fetch<ServerChannelsResponse>(
    `/api/v1/federated/servers/${serverId}/channels`,
  );
}

/**
 * Use an invite code on a remote instance to join a server.
 */
export function useFederatedInvite(
  client: ApiClient,
  code: string,
): Promise<JoinServerResponse> {
  return client.fetch<JoinServerResponse>(
    `/api/v1/federated/invites/${code}/use`,
    { method: "POST" },
  );
}
