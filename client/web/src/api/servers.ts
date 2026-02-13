/**
 * Servers API endpoints — delegates to @cairn/proto.
 */

import { serversApi } from "@cairn/proto";
import { client } from "./client.ts";
import type { Channel } from "./channels.ts";

export type { Server, ServerMember, ServerRole } from "@cairn/proto/api";
export type { Channel };

export function listServers() {
  return serversApi.listServers(client);
}

export function createServer(params: {
  name: string;
  description?: string;
}) {
  return serversApi.createServer(client, params);
}

export function getServer(serverId: string) {
  return serversApi.getServer(client, serverId);
}

export function updateServer(
  serverId: string,
  params: { name?: string; description?: string },
) {
  return serversApi.updateServer(client, serverId, params);
}

export function deleteServer(serverId: string) {
  return serversApi.deleteServer(client, serverId);
}

export function getServerMembers(serverId: string) {
  return serversApi.getServerMembers(client, serverId);
}

export function getServerChannels(serverId: string) {
  return serversApi.getServerChannels(client, serverId);
}

export function createServerChannel(
  serverId: string,
  params: { name: string; type?: string; description?: string },
) {
  return serversApi.createServerChannel(client, serverId, params);
}

export function getServerRoles(serverId: string) {
  return serversApi.getServerRoles(client, serverId);
}

export function joinServer(serverId: string) {
  return serversApi.joinServer(client, serverId);
}

export function leaveServer(serverId: string) {
  return serversApi.leaveServer(client, serverId);
}
