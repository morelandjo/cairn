/**
 * Auth store — manages user, tokens, login/register/logout.
 * Persists tokens to localStorage.
 */

import { create } from "zustand";
import { configureClient } from "../api/client.ts";
import * as authApi from "../api/auth.ts";
import type { User } from "../api/auth.ts";
import { connectSocket, disconnectSocket } from "../api/socket.ts";
import { loadKeySync, storeKeySync, deleteKeySync } from "../lib/keyStorage.ts";

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  recoveryCodes: string[] | null;
  isLoading: boolean;
  error: string | null;

  login: (username: string, password: string) => Promise<{ requiresTotp?: boolean; userId?: string }>;
  register: (username: string, password: string, displayName?: string, extra?: { altcha?: string; website?: string }) => Promise<void>;
  logout: () => void;
  refreshTokens: () => Promise<void>;
  loadSession: () => Promise<void>;
  clearRecoveryCodes: () => void;
  setError: (error: string | null) => void;
}

function saveTokens(accessToken: string | null, refreshToken: string | null) {
  if (accessToken) {
    storeKeySync("access_token", accessToken);
  } else {
    deleteKeySync("access_token");
  }
  if (refreshToken) {
    storeKeySync("refresh_token", refreshToken);
  } else {
    deleteKeySync("refresh_token");
  }
}

function loadTokens() {
  return {
    accessToken: loadKeySync("access_token"),
    refreshToken: loadKeySync("refresh_token"),
  };
}

export const useAuthStore = create<AuthState>((set, get) => {
  // Configure the API client to use this store's tokens
  configureClient({
    getAccessToken: () => get().accessToken,
    getRefreshToken: () => get().refreshToken,
    setTokens: (access, refresh) => {
      set({ accessToken: access, refreshToken: refresh });
      saveTokens(access, refresh);
    },
    onAuthFailure: () => {
      get().logout();
    },
  });

  return {
    user: null,
    accessToken: null,
    refreshToken: null,
    recoveryCodes: null,
    isLoading: false,
    error: null,

    login: async (username, password) => {
      set({ isLoading: true, error: null });
      try {
        const result = await authApi.login({ username, password });
        if ("requires_totp" in result && result.requires_totp) {
          set({ isLoading: false });
          return { requiresTotp: true, userId: result.user_id };
        }
        const data = result as authApi.LoginResponse;
        set({
          user: data.user,
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
          isLoading: false,
        });
        saveTokens(data.access_token, data.refresh_token);
        connectSocket(data.access_token);
        return {};
      } catch (err) {
        const message = err instanceof Error ? err.message : "Login failed";
        set({ isLoading: false, error: message });
        throw err;
      }
    },

    register: async (username, password, displayName, extra) => {
      set({ isLoading: true, error: null });
      try {
        const data = await authApi.register({
          username,
          password,
          display_name: displayName,
          ...extra,
        });
        set({
          user: data.user,
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
          recoveryCodes: data.recovery_codes,
          isLoading: false,
        });
        saveTokens(data.access_token, data.refresh_token);
        connectSocket(data.access_token);
      } catch (err) {
        const message = err instanceof Error ? err.message : "Registration failed";
        set({ isLoading: false, error: message });
        throw err;
      }
    },

    logout: () => {
      disconnectSocket();
      set({
        user: null,
        accessToken: null,
        refreshToken: null,
        recoveryCodes: null,
        error: null,
      });
      saveTokens(null, null);
    },

    refreshTokens: async () => {
      const { refreshToken } = get();
      if (!refreshToken) return;
      try {
        const data = await authApi.refreshTokens(refreshToken);
        set({
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
        });
        saveTokens(data.access_token, data.refresh_token);
      } catch {
        get().logout();
      }
    },

    loadSession: async () => {
      const tokens = loadTokens();
      if (!tokens.accessToken) return;
      set({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, isLoading: true });
      try {
        const data = await authApi.getMe();
        set({ user: data.user, isLoading: false });
        connectSocket(tokens.accessToken);
      } catch {
        // Token may be expired, try refresh
        if (tokens.refreshToken) {
          try {
            const refreshData = await authApi.refreshTokens(tokens.refreshToken);
            set({
              accessToken: refreshData.access_token,
              refreshToken: refreshData.refresh_token,
            });
            saveTokens(refreshData.access_token, refreshData.refresh_token);
            const meData = await authApi.getMe();
            set({ user: meData.user, isLoading: false });
            connectSocket(refreshData.access_token);
          } catch {
            set({ isLoading: false });
            get().logout();
          }
        } else {
          set({ isLoading: false });
          get().logout();
        }
      }
    },

    clearRecoveryCodes: () => {
      set({ recoveryCodes: null });
    },

    setError: (error) => {
      set({ error });
    },
  };
});
