/**
 * Connection store — manages WebSocket connections to multiple instances.
 *
 * Each instance gets its own socket, API client, and token.
 * The home instance uses the normal JWT token; remote instances
 * use federated auth tokens.
 */

import { create } from "zustand";
// @ts-expect-error phoenix has no type declarations
import { Socket } from "phoenix";

export interface InstanceConnection {
  domain: string;
  token: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  socket: any;
  status: "connecting" | "connected" | "disconnected" | "error";
  isHome: boolean;
}

interface ConnectionState {
  connections: Map<string, InstanceConnection>;

  /** Add/update a connection for a domain */
  connect: (domain: string, token: string, isHome: boolean, wsUrl?: string) => void;
  /** Disconnect from a specific domain */
  disconnect: (domain: string) => void;
  /** Disconnect from all domains */
  disconnectAll: () => void;
  /** Get a connection by domain */
  getConnection: (domain: string) => InstanceConnection | undefined;
  /** Get the home instance connection */
  getHomeConnection: () => InstanceConnection | undefined;
  /** Update connection status */
  setStatus: (domain: string, status: InstanceConnection["status"]) => void;
}

export const useConnectionStore = create<ConnectionState>((set, get) => ({
  connections: new Map(),

  connect: (domain, token, isHome, wsUrl) => {
    const existing = get().connections.get(domain);
    if (existing?.socket) {
      existing.socket.disconnect();
    }

    const endpoint = wsUrl || (isHome ? "/socket" : `wss://${domain}/socket`);
    const socket = new Socket(endpoint, { params: { token } });

    socket.onOpen(() => {
      get().setStatus(domain, "connected");
    });

    socket.onError(() => {
      get().setStatus(domain, "error");
    });

    socket.onClose(() => {
      get().setStatus(domain, "disconnected");
    });

    socket.connect();

    const conn: InstanceConnection = {
      domain,
      token,
      socket,
      status: "connecting",
      isHome,
    };

    set((state) => {
      const next = new Map(state.connections);
      next.set(domain, conn);
      return { connections: next };
    });
  },

  disconnect: (domain) => {
    const conn = get().connections.get(domain);
    if (conn?.socket) {
      conn.socket.disconnect();
    }
    set((state) => {
      const next = new Map(state.connections);
      next.delete(domain);
      return { connections: next };
    });
  },

  disconnectAll: () => {
    for (const conn of get().connections.values()) {
      conn.socket?.disconnect();
    }
    set({ connections: new Map() });
  },

  getConnection: (domain) => {
    return get().connections.get(domain);
  },

  getHomeConnection: () => {
    for (const conn of get().connections.values()) {
      if (conn.isHome) return conn;
    }
    return undefined;
  },

  setStatus: (domain, status) => {
    set((state) => {
      const conn = state.connections.get(domain);
      if (!conn) return state;
      const next = new Map(state.connections);
      next.set(domain, { ...conn, status });
      return { connections: next };
    });
  },
}));
