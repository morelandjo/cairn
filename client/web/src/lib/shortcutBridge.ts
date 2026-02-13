/**
 * Shortcut bridge — listens for global shortcut events from Tauri
 * and dispatches actions to the voice store.
 */

import { isTauri } from "./desktopBridge.ts";

type InvokeFn = (cmd: string, args?: Record<string, unknown>) => Promise<unknown>;

interface ShortcutConfig {
  toggleMute: string;
  toggleDeafen: string;
  pushToTalk: string | null;
}

const DEFAULT_SHORTCUTS: ShortcutConfig = {
  toggleMute: "CmdOrCtrl+Shift+M",
  toggleDeafen: "CmdOrCtrl+Shift+D",
  pushToTalk: null,
};

let cleanup: (() => void) | null = null;

/** Initialize global shortcut listeners. Call once after app loads. */
export async function initShortcuts(callbacks: {
  onToggleMute: () => void;
  onToggleDeafen: () => void;
  onPushToTalkStart?: () => void;
  onPushToTalkEnd?: () => void;
}): Promise<void> {
  if (!isTauri) return;

  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const { listen } = await import("@tauri-apps/api/event");

    const unlisteners: Array<() => void> = [];

    // Register default shortcuts
    const config = loadShortcutConfig();

    if (config.toggleMute) {
      await (invoke as InvokeFn)("register_shortcut", {
        shortcut: config.toggleMute,
        action: "toggle-mute",
      });
      const u = await listen("shortcut:toggle-mute", () => {
        callbacks.onToggleMute();
      });
      unlisteners.push(u);
    }

    if (config.toggleDeafen) {
      await (invoke as InvokeFn)("register_shortcut", {
        shortcut: config.toggleDeafen,
        action: "toggle-deafen",
      });
      const u = await listen("shortcut:toggle-deafen", () => {
        callbacks.onToggleDeafen();
      });
      unlisteners.push(u);
    }

    if (config.pushToTalk) {
      await (invoke as InvokeFn)("register_shortcut", {
        shortcut: config.pushToTalk,
        action: "push-to-talk",
      });
      const u = await listen("shortcut:push-to-talk", () => {
        callbacks.onPushToTalkStart?.();
      });
      unlisteners.push(u);
    }

    cleanup = () => {
      for (const u of unlisteners) u();
    };
  } catch (e) {
    console.error("Failed to initialize global shortcuts:", e);
  }
}

/** Clean up shortcut listeners. */
export function destroyShortcuts(): void {
  cleanup?.();
  cleanup = null;
}

/** Load shortcut config from localStorage. */
function loadShortcutConfig(): ShortcutConfig {
  try {
    const saved = localStorage.getItem("murmur_shortcuts");
    if (saved) return { ...DEFAULT_SHORTCUTS, ...JSON.parse(saved) };
  } catch {
    // ignore
  }
  return { ...DEFAULT_SHORTCUTS };
}

/** Save shortcut config to localStorage. */
export function saveShortcutConfig(config: Partial<ShortcutConfig>): void {
  const current = loadShortcutConfig();
  const merged = { ...current, ...config };
  localStorage.setItem("murmur_shortcuts", JSON.stringify(merged));
}

export { DEFAULT_SHORTCUTS };
export type { ShortcutConfig };
