/**
 * Cross-instance DM API endpoints — delegates to @cairn/proto.
 */

import { dmApi } from "@cairn/proto";
import type { ApiClient } from "@cairn/proto";
import { client } from "./client.ts";

/**
 * Create a federated DM with a remote user.
 */
export function createFederatedDm(
  recipientDid: string,
  recipientInstance: string,
) {
  return dmApi.createFederatedDm(client, recipientDid, recipientInstance);
}

/**
 * List pending DM requests received by the current user.
 */
export function listDmRequests() {
  return dmApi.listDmRequests(client);
}

/**
 * List DM requests sent by the current user.
 */
export function listSentDmRequests() {
  return dmApi.listSentDmRequests(client);
}

/**
 * Accept or reject a DM request.
 */
export function respondToDmRequest(
  requestId: string,
  status: "accepted" | "rejected",
) {
  return dmApi.respondToDmRequest(client, requestId, status);
}

/**
 * Block a DM request sender.
 */
export function blockDmSender(requestId: string) {
  return dmApi.blockDmSender(client, requestId);
}

/**
 * Fetch a key bundle from a remote instance for cross-instance X3DH.
 * Uses a remote client configured with the target instance URL.
 */
export function fetchFederatedKeyBundle(
  remoteClient: ApiClient,
  didSuffix: string,
) {
  return dmApi.fetchFederatedKeyBundle(remoteClient, didSuffix);
}
