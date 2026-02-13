/**
 * Server URL store — manages the home server URL for desktop (Tauri) builds.
 * In web mode (SPA served by Phoenix), relative URLs work fine so this is a no-op.
 * In desktop mode, the user must configure a server URL on first launch.
 */

import { create } from "zustand";
import { isTauri } from "../lib/desktopBridge.ts";
import { setBaseUrl } from "../api/client.ts";
import { setSocketBaseUrl } from "../api/socket.ts";

const STORAGE_KEY = "cairn_server_url";

interface ServerUrlState {
  /** null = not configured, "" = web mode (relative URLs) */
  serverUrl: string | null;
  /** Prevents UI flash before URL is checked */
  isLoaded: boolean;
  loadServerUrl: () => void;
  setServerUrl: (url: string) => void;
  clearServerUrl: () => void;
}

export const useServerUrlStore = create<ServerUrlState>((set) => ({
  serverUrl: null,
  isLoaded: false,

  loadServerUrl() {
    if (!isTauri) {
      // Web mode — relative URLs, no server URL needed
      set({ serverUrl: "", isLoaded: true });
      return;
    }
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      setBaseUrl(saved);
      setSocketBaseUrl(saved);
      set({ serverUrl: saved, isLoaded: true });
    } else {
      set({ serverUrl: null, isLoaded: true });
    }
  },

  setServerUrl(url: string) {
    localStorage.setItem(STORAGE_KEY, url);
    setBaseUrl(url);
    setSocketBaseUrl(url);
    set({ serverUrl: url });
  },

  clearServerUrl() {
    localStorage.removeItem(STORAGE_KEY);
    set({ serverUrl: null });
  },
}));
