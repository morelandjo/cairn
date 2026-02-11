/**
 * Identity API endpoints for DID operations.
 */

import type { ApiClient } from "./client.js";
import type { DIDDocument, DIDOperation } from "../types.js";

export interface RotateSigningKeyParams {
  new_signing_key: string;
  rotation_private_key: string;
}

export interface RotateSigningKeyResponse {
  ok: boolean;
  did: string;
}

export interface DIDOperationsResponse {
  did: string;
  operations: DIDOperation[];
}

/**
 * Rotate the current user's signing key.
 * Requires the new signing public key and the rotation private key (both base64).
 */
export function rotateSigningKey(
  client: ApiClient,
  params: RotateSigningKeyParams,
): Promise<RotateSigningKeyResponse> {
  return client.fetch<RotateSigningKeyResponse>(
    "/api/v1/users/me/did/rotate-signing-key",
    {
      method: "POST",
      body: JSON.stringify(params),
    },
  );
}

/**
 * Get a DID document by resolving the DID.
 * This is a public endpoint (no auth required).
 */
export function getDIDDocument(
  client: ApiClient,
  did: string,
): Promise<DIDDocument> {
  const suffix = did.replace("did:murmuring:", "");
  return client.fetch<DIDDocument>(`/.well-known/did/${suffix}`);
}

/**
 * Get the raw operation chain for a DID.
 * This is a public endpoint (no auth required).
 */
export function getDIDOperations(
  client: ApiClient,
  did: string,
): Promise<DIDOperationsResponse> {
  const suffix = did.replace("did:murmuring:", "");
  return client.fetch<DIDOperationsResponse>(
    `/.well-known/did/${suffix}/operations`,
  );
}
