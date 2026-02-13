/**
 * Invite management API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface Invite {
  id: string;
  code: string;
  channel_id: string;
  max_uses: number | null;
  uses: number;
  expires_at: string | null;
}

export interface InviteInfo {
  code: string;
  channel_name: string;
  channel_id: string;
}

export function createInvite(
  client: ApiClient,
  params: {
    channel_id: string;
    max_uses?: number;
    expires_at?: string;
  },
): Promise<{ invite: Invite }> {
  return client.fetch<{ invite: Invite }>("/api/v1/invites", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function getInvite(
  client: ApiClient,
  code: string,
): Promise<{ invite: InviteInfo }> {
  return client.fetch<{ invite: InviteInfo }>(`/api/v1/invites/${code}`);
}

export function useInvite(
  client: ApiClient,
  code: string,
): Promise<{ channel: { id: string; name: string; type: string } }> {
  return client.fetch<{ channel: { id: string; name: string; type: string } }>(
    `/api/v1/invites/${code}/use`,
    { method: "POST" },
  );
}
