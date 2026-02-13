/**
 * Notification Preferences — delegates to @cairn/proto.
 */

import { notificationsApi } from "@cairn/proto";
import { client } from "./client";

export type { NotificationPreference } from "@cairn/proto/api";

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
