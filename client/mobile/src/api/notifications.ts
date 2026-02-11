/**
 * Notification Preferences — delegates to @murmuring/proto.
 */

import { notificationsApi } from "@murmuring/proto";
import { client } from "./client";

export type { NotificationPreference } from "@murmuring/proto/api";

export function getPreferences() {
  return notificationsApi.getPreferences(client);
}

export function updatePreference(params: {
  server_id?: string;
  channel_id?: string;
  level?: string;
  dnd_enabled?: boolean;
  quiet_hours_start?: string;
  quiet_hours_end?: string;
}) {
  return notificationsApi.updatePreference(client, params);
}
