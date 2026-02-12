/**
 * Invite management — delegates to @cairn/proto.
 */

import { invitesApi } from "@cairn/proto";
import { client } from "./client.ts";

export type { Invite, InviteInfo } from "@cairn/proto/api";

export function createInvite(params: {
  channel_id: string;
  max_uses?: number;
  expires_at?: string;
}) {
  return invitesApi.createInvite(client, params);
}

export function getInvite(code: string) {
  return invitesApi.getInvite(client, code);
}

export function useInvite(code: string) {
  return invitesApi.useInvite(client, code);
}
