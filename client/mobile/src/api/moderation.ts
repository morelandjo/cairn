/**
 * Moderation API endpoints — delegates to @murmuring/proto.
 */

import { moderationApi } from "@murmuring/proto";
import { client } from "./client";

export type {
  Mute,
  Ban,
  ModLogEntry,
  MessageReport,
  AutoModRule,
} from "@murmuring/proto/api";

export function muteUser(
  serverId: string,
  params: { user_id: string; reason?: string; duration_minutes?: number },
) {
  return moderationApi.muteUser(client, serverId, params);
}

export function unmuteUser(serverId: string, userId: string) {
  return moderationApi.unmuteUser(client, serverId, userId);
}

export function listMutes(serverId: string) {
  return moderationApi.listMutes(client, serverId);
}

export function kickUser(serverId: string, userId: string) {
  return moderationApi.kickUser(client, serverId, userId);
}

export function banUser(
  serverId: string,
  params: { user_id: string; reason?: string; duration_minutes?: number },
) {
  return moderationApi.banUser(client, serverId, params);
}

export function unbanUser(serverId: string, userId: string) {
  return moderationApi.unbanUser(client, serverId, userId);
}

export function listBans(serverId: string) {
  return moderationApi.listBans(client, serverId);
}

export function getModerationLog(
  serverId: string,
  opts?: { limit?: number },
) {
  return moderationApi.getModerationLog(client, serverId, opts);
}

export function reportMessage(
  messageId: string,
  params: { reason: string; details?: string },
) {
  return moderationApi.reportMessage(client, messageId, params);
}

export function listReports(serverId: string) {
  return moderationApi.listReports(client, serverId);
}

export function resolveReport(
  serverId: string,
  reportId: string,
  params: { status: string; resolution_action?: string },
) {
  return moderationApi.resolveReport(client, serverId, reportId, params);
}

export function listAutoModRules(serverId: string) {
  return moderationApi.listAutoModRules(client, serverId);
}

export function createAutoModRule(
  serverId: string,
  params: {
    rule_type: string;
    enabled: boolean;
    config: Record<string, unknown>;
  },
) {
  return moderationApi.createAutoModRule(client, serverId, params);
}

export function updateAutoModRule(
  serverId: string,
  ruleId: string,
  params: { enabled?: boolean; config?: Record<string, unknown> },
) {
  return moderationApi.updateAutoModRule(client, serverId, ruleId, params);
}

export function deleteAutoModRule(serverId: string, ruleId: string) {
  return moderationApi.deleteAutoModRule(client, serverId, ruleId);
}
