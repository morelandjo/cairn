/**
 * Settings store — biometric lock, auto-lock timeout, preferences.
 */

import { create } from "zustand";
import { loadKeySync, storeKeySync } from "../lib/keyStorage";

type AutoLockTimeout = "1min" | "5min" | "15min" | "never";

interface SettingsState {
  biometricEnabled: boolean;
  autoLockTimeout: AutoLockTimeout;
  lastBackgroundTime: number | null;

  toggleBiometric: () => void;
  setAutoLockTimeout: (timeout: AutoLockTimeout) => void;
  setLastBackgroundTime: (time: number | null) => void;
  shouldRequireAuth: () => boolean;
}

function getTimeoutMs(timeout: AutoLockTimeout): number {
  switch (timeout) {
    case "1min":
      return 60_000;
    case "5min":
      return 300_000;
    case "15min":
      return 900_000;
    case "never":
      return Infinity;
  }
}

export const useSettingsStore = create<SettingsState>((set, get) => ({
  biometricEnabled: loadKeySync("biometric_enabled") === "true",
  autoLockTimeout: (loadKeySync("auto_lock_timeout") as AutoLockTimeout) ?? "5min",
  lastBackgroundTime: null,

  toggleBiometric: () => {
    const newValue = !get().biometricEnabled;
    storeKeySync("biometric_enabled", String(newValue));
    set({ biometricEnabled: newValue });
  },

  setAutoLockTimeout: (timeout) => {
    storeKeySync("auto_lock_timeout", timeout);
    set({ autoLockTimeout: timeout });
  },

  setLastBackgroundTime: (time) => {
    set({ lastBackgroundTime: time });
  },

  shouldRequireAuth: () => {
    const { biometricEnabled, autoLockTimeout, lastBackgroundTime } = get();
    if (!biometricEnabled) return false;
    if (autoLockTimeout === "never") return false;
    if (lastBackgroundTime === null) return true; // First launch

    const elapsed = Date.now() - lastBackgroundTime;
    return elapsed >= getTimeoutMs(autoLockTimeout);
  },
}));
