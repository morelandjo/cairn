/**
 * Cross-instance DM API endpoints.
 */

import type { ApiClient } from "./client.js";
import type { DmRequest, FederatedKeyBundle } from "../types.js";

export interface CreateFederatedDmResponse {
  channel_id: string;
  request_id: string;
  status: string;
}

export interface DmRequestsResponse {
  requests: DmRequest[];
}

export interface RespondToDmRequestResponse {
  id: string;
  status: string;
  channel_id: string;
}

/**
 * Create a federated DM with a remote user.
 * Called on the initiator's home instance.
 */
export function createFederatedDm(
  client: ApiClient,
  recipientDid: string,
  recipientInstance: string,
): Promise<CreateFederatedDmResponse> {
  return client.fetch<CreateFederatedDmResponse>("/api/v1/dm/federated", {
    method: "POST",
    body: JSON.stringify({
      recipient_did: recipientDid,
      recipient_instance: recipientInstance,
    }),
  });
}

/**
 * List pending DM requests received by the current user.
 */
export function listDmRequests(
  client: ApiClient,
): Promise<DmRequestsResponse> {
  return client.fetch<DmRequestsResponse>("/api/v1/dm/requests");
}

/**
 * List DM requests sent by the current user.
 */
export function listSentDmRequests(
  client: ApiClient,
): Promise<DmRequestsResponse> {
  return client.fetch<DmRequestsResponse>("/api/v1/dm/requests/sent");
}

/**
 * Accept or reject a DM request.
 */
export function respondToDmRequest(
  client: ApiClient,
  requestId: string,
  status: "accepted" | "rejected",
): Promise<RespondToDmRequestResponse> {
  return client.fetch<RespondToDmRequestResponse>(
    `/api/v1/dm/requests/${requestId}/respond`,
    {
      method: "POST",
      body: JSON.stringify({ status }),
    },
  );
}

/**
 * Block a DM request sender (rejects and blocks their DID).
 */
export function blockDmSender(
  client: ApiClient,
  requestId: string,
): Promise<{ ok: boolean; blocked: boolean }> {
  return client.fetch(`/api/v1/dm/requests/${requestId}/block`, {
    method: "POST",
  });
}

/**
 * Fetch a key bundle for a remote user by DID, via federation.
 * Called on the remote user's home instance.
 */
export function fetchFederatedKeyBundle(
  client: ApiClient,
  didSuffix: string,
): Promise<FederatedKeyBundle> {
  return client.fetch<FederatedKeyBundle>(
    `/api/v1/federation/users/${didSuffix}/keys`,
  );
}
