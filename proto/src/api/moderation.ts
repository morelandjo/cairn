/**
 * Moderation API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface Mute {
  id: string;
  server_id: string;
  user_id: string;
  channel_id: string | null;
  reason: string | null;
  muted_by_id: string;
  expires_at: string | null;
  inserted_at: string;
}

export interface Ban {
  id: string;
  server_id: string;
  user_id: string;
  reason: string | null;
  banned_by_id: string;
  expires_at: string | null;
  inserted_at: string;
}

export interface ModLogEntry {
  id: string;
  server_id: string;
  moderator_id: string;
  target_user_id: string;
  action: string;
  details: string | null;
  inserted_at: string;
}

export interface MessageReport {
  id: string;
  message_id: string;
  reporter_id: string;
  server_id: string;
  reason: string;
  details: string | null;
  status: string;
  resolved_by_id: string | null;
  resolution_action: string | null;
  inserted_at: string;
}

export interface AutoModRule {
  id: string;
  server_id: string;
  rule_type: string;
  enabled: boolean;
  config: Record<string, unknown>;
}

// --- Mutes ---

export function muteUser(
  client: ApiClient,
  serverId: string,
  params: { user_id: string; reason?: string; duration_minutes?: number },
): Promise<{ mute: Mute }> {
  return client.fetch<{ mute: Mute }>(`/api/v1/servers/${serverId}/mutes`, {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function unmuteUser(
  client: ApiClient,
  serverId: string,
  userId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/mutes/${userId}`,
    { method: "DELETE" },
  );
}

export function listMutes(
  client: ApiClient,
  serverId: string,
): Promise<{ mutes: Mute[] }> {
  return client.fetch<{ mutes: Mute[] }>(`/api/v1/servers/${serverId}/mutes`);
}

// --- Kicks ---

export function kickUser(
  client: ApiClient,
  serverId: string,
  userId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/kicks/${userId}`,
    { method: "POST" },
  );
}

// --- Bans ---

export function banUser(
  client: ApiClient,
  serverId: string,
  params: { user_id: string; reason?: string; duration_minutes?: number },
): Promise<{ ban: Ban }> {
  return client.fetch<{ ban: Ban }>(`/api/v1/servers/${serverId}/bans`, {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function unbanUser(
  client: ApiClient,
  serverId: string,
  userId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/bans/${userId}`,
    { method: "DELETE" },
  );
}

export function listBans(
  client: ApiClient,
  serverId: string,
): Promise<{ bans: Ban[] }> {
  return client.fetch<{ bans: Ban[] }>(`/api/v1/servers/${serverId}/bans`);
}

// --- Moderation Log ---

export function getModerationLog(
  client: ApiClient,
  serverId: string,
  opts?: { limit?: number },
): Promise<{ entries: ModLogEntry[] }> {
  const params = new URLSearchParams();
  if (opts?.limit) params.set("limit", String(opts.limit));
  const qs = params.toString();
  const path = `/api/v1/servers/${serverId}/moderation-log${qs ? `?${qs}` : ""}`;
  return client.fetch<{ entries: ModLogEntry[] }>(path);
}

// --- Reports ---

export function reportMessage(
  client: ApiClient,
  messageId: string,
  params: { reason: string; details?: string },
): Promise<{ report: MessageReport }> {
  return client.fetch<{ report: MessageReport }>(
    `/api/v1/messages/${messageId}/report`,
    {
      method: "POST",
      body: JSON.stringify(params),
    },
  );
}

export function listReports(
  client: ApiClient,
  serverId: string,
): Promise<{ reports: MessageReport[] }> {
  return client.fetch<{ reports: MessageReport[] }>(
    `/api/v1/servers/${serverId}/reports`,
  );
}

export function resolveReport(
  client: ApiClient,
  serverId: string,
  reportId: string,
  params: { status: string; resolution_action?: string },
): Promise<{ report: MessageReport }> {
  return client.fetch<{ report: MessageReport }>(
    `/api/v1/servers/${serverId}/reports/${reportId}`,
    {
      method: "PUT",
      body: JSON.stringify(params),
    },
  );
}

// --- Auto-Mod Rules ---

export function listAutoModRules(
  client: ApiClient,
  serverId: string,
): Promise<{ rules: AutoModRule[] }> {
  return client.fetch<{ rules: AutoModRule[] }>(
    `/api/v1/servers/${serverId}/auto-mod-rules`,
  );
}

export function createAutoModRule(
  client: ApiClient,
  serverId: string,
  params: {
    rule_type: string;
    enabled: boolean;
    config: Record<string, unknown>;
  },
): Promise<{ rule: AutoModRule }> {
  return client.fetch<{ rule: AutoModRule }>(
    `/api/v1/servers/${serverId}/auto-mod-rules`,
    {
      method: "POST",
      body: JSON.stringify(params),
    },
  );
}

export function updateAutoModRule(
  client: ApiClient,
  serverId: string,
  ruleId: string,
  params: { enabled?: boolean; config?: Record<string, unknown> },
): Promise<{ rule: AutoModRule }> {
  return client.fetch<{ rule: AutoModRule }>(
    `/api/v1/servers/${serverId}/auto-mod-rules/${ruleId}`,
    {
      method: "PUT",
      body: JSON.stringify(params),
    },
  );
}

export function deleteAutoModRule(
  client: ApiClient,
  serverId: string,
  ruleId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(
    `/api/v1/servers/${serverId}/auto-mod-rules/${ruleId}`,
    { method: "DELETE" },
  );
}
