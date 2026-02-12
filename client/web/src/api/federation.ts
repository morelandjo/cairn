/**
 * Federation API endpoints — delegates to @cairn/proto.
 *
 * requestFederatedToken() is called on the home instance.
 * For remote instance calls (join, channels, invite), create a separate
 * ApiClient configured with the remote instance's base URL and federated token.
 */

import { federationApi } from "@cairn/proto";
import { ApiClient } from "@cairn/proto";
import { client } from "./client.ts";

/**
 * Request a federated auth token for a target instance.
 * Called on the home instance with the user's normal auth.
 */
export function requestFederatedToken(targetInstance: string) {
  return federationApi.requestFederatedToken(client, targetInstance);
}

/**
 * Create a client configured for a remote instance with a federated token.
 */
export function createRemoteClient(
  baseUrl: string,
  federatedToken: string,
): ApiClient {
  const remoteClient = new ApiClient({ baseUrl });
  remoteClient.configure({
    getAccessToken: () => federatedToken,
    getRefreshToken: () => null,
    setTokens: () => {},
    onAuthFailure: () => {},
  });
  return remoteClient;
}

/**
 * Join a server on a remote instance.
 */
export function joinRemoteServer(remoteClient: ApiClient, serverId: string) {
  return federationApi.joinServer(remoteClient, serverId);
}

/**
 * List channels on a remote server.
 */
export function getRemoteServerChannels(
  remoteClient: ApiClient,
  serverId: string,
) {
  return federationApi.getServerChannels(remoteClient, serverId);
}

/**
 * Use an invite code on a remote instance.
 */
export function useRemoteFederatedInvite(
  remoteClient: ApiClient,
  code: string,
) {
  return federationApi.useFederatedInvite(remoteClient, code);
}
