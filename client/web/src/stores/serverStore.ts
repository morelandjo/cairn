/**
 * Server store — manages servers list, current server selection.
 */

import { create } from "zustand";
import * as serversApi from "../api/servers.ts";
import type { Server } from "../api/servers.ts";

interface ServerState {
  servers: Server[];
  currentServerId: string | null;
  isLoadingServers: boolean;

  fetchServers: () => Promise<void>;
  selectServer: (serverId: string | null) => void;
  createServer: (name: string, description?: string) => Promise<Server>;
}

export const useServerStore = create<ServerState>((set) => ({
  servers: [],
  currentServerId: null,
  isLoadingServers: false,

  fetchServers: async () => {
    set({ isLoadingServers: true });
    try {
      const data = await serversApi.listServers();
      set({ servers: data.servers, isLoadingServers: false });
    } catch (err) {
      console.error("Failed to fetch servers:", err);
      set({ isLoadingServers: false });
    }
  },

  selectServer: (serverId) => {
    set({ currentServerId: serverId });
  },

  createServer: async (name, description) => {
    const data = await serversApi.createServer({ name, description });
    set((state) => ({
      servers: [...state.servers, data.server],
      currentServerId: data.server.id,
    }));
    return data.server;
  },
}));
