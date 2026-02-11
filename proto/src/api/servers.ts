/**
 * Servers API endpoints.
 */

import type { ApiClient } from "./client.js";
import type { Channel } from "./channels.js";

export interface Server {
  id: string;
  name: string;
  description: string | null;
  icon_key: string | null;
  creator_id: string;
  inserted_at: string;
  /** Domain of the instance this server belongs to. Absent or "home" for local servers. */
  instance_domain?: string;
}

export interface ServerMember {
  id: string;
  username: string;
  display_name: string | null;
  role_id: string | null;
  role_name: string | null;
}

export interface ServerRole {
  id: string;
  name: string;
  permissions: Record<string, boolean>;
  priority: number;
  color: string | null;
}

export function listServers(
  client: ApiClient,
): Promise<{ servers: Server[] }> {
  return client.fetch<{ servers: Server[] }>("/api/v1/servers");
}

export function createServer(
  client: ApiClient,
  params: { name: string; description?: string },
): Promise<{ server: Server }> {
  return client.fetch<{ server: Server }>("/api/v1/servers", {
    method: "POST",
    body: JSON.stringify(params),
  });
}

export function getServer(
  client: ApiClient,
  serverId: string,
): Promise<{ server: Server }> {
  return client.fetch<{ server: Server }>(`/api/v1/servers/${serverId}`);
}

export function updateServer(
  client: ApiClient,
  serverId: string,
  params: { name?: string; description?: string },
): Promise<{ server: Server }> {
  return client.fetch<{ server: Server }>(`/api/v1/servers/${serverId}`, {
    method: "PUT",
    body: JSON.stringify(params),
  });
}

export function deleteServer(
  client: ApiClient,
  serverId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(`/api/v1/servers/${serverId}`, {
    method: "DELETE",
  });
}

export function getServerMembers(
  client: ApiClient,
  serverId: string,
): Promise<{ members: ServerMember[] }> {
  return client.fetch<{ members: ServerMember[] }>(
    `/api/v1/servers/${serverId}/members`,
  );
}

export function getServerChannels(
  client: ApiClient,
  serverId: string,
): Promise<{ channels: Channel[] }> {
  return client.fetch<{ channels: Channel[] }>(
    `/api/v1/servers/${serverId}/channels`,
  );
}

export function createServerChannel(
  client: ApiClient,
  serverId: string,
  params: { name: string; type?: string; description?: string },
): Promise<{ channel: Channel }> {
  return client.fetch<{ channel: Channel }>(
    `/api/v1/servers/${serverId}/channels`,
    {
      method: "POST",
      body: JSON.stringify(params),
    },
  );
}

export function getServerRoles(
  client: ApiClient,
  serverId: string,
): Promise<{ roles: ServerRole[] }> {
  return client.fetch<{ roles: ServerRole[] }>(
    `/api/v1/servers/${serverId}/roles`,
  );
}

export function joinServer(
  client: ApiClient,
  serverId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(`/api/v1/servers/${serverId}/join`, {
    method: "POST",
  });
}

export function leaveServer(
  client: ApiClient,
  serverId: string,
): Promise<{ ok: boolean }> {
  return client.fetch<{ ok: boolean }>(`/api/v1/servers/${serverId}/leave`, {
    method: "POST",
  });
}
