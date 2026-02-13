/**
 * Notification Preferences API endpoints.
 */

import type { ApiClient } from "./client.js";

export interface NotificationPreference {
  id: string;
  server_id: string | null;
  channel_id: string | null;
  level: "all" | "mentions" | "nothing";
  dnd_enabled: boolean;
  quiet_hours_start: string | null;
  quiet_hours_end: string | null;
}

export function getPreferences(
  client: ApiClient,
): Promise<{ preferences: NotificationPreference[] }> {
  return client.fetch<{ preferences: NotificationPreference[] }>(
    "/api/v1/users/me/notification-preferences",
  );
}

export function updatePreference(
  client: ApiClient,
  params: {
    server_id?: string;
    channel_id?: string;
    level?: string;
    dnd_enabled?: boolean;
    quiet_hours_start?: string;
    quiet_hours_end?: string;
  },
): Promise<{ preference: NotificationPreference }> {
  return client.fetch<{ preference: NotificationPreference }>(
    "/api/v1/users/me/notification-preferences",
    { method: "PUT", body: JSON.stringify(params) },
  );
}
