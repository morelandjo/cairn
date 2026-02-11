/**
 * Keyboard shortcut settings for desktop — allows users to view and
 * configure global hotkeys for voice controls.
 */

import { useState } from "react";
import { isTauri } from "../lib/desktopBridge.ts";
import {
  DEFAULT_SHORTCUTS,
  saveShortcutConfig,
  type ShortcutConfig,
} from "../lib/shortcutBridge.ts";

function loadConfig(): ShortcutConfig {
  try {
    const saved = localStorage.getItem("murmur_shortcuts");
    if (saved) return { ...DEFAULT_SHORTCUTS, ...JSON.parse(saved) };
  } catch {
    // ignore
  }
  return { ...DEFAULT_SHORTCUTS };
}

export function ShortcutSettings() {
  const [config, setConfig] = useState<ShortcutConfig>(loadConfig);

  if (!isTauri) return null;

  const update = (key: keyof ShortcutConfig, value: string | null) => {
    const newConfig = { ...config, [key]: value || null };
    setConfig(newConfig);
    saveShortcutConfig(newConfig);
  };

  return (
    <div className="shortcut-settings">
      <h3>Keyboard Shortcuts</h3>
      <p className="shortcut-hint">
        These shortcuts work even when the app is not focused.
        Restart the app after changing shortcuts.
      </p>
      <div className="shortcut-row">
        <label htmlFor="shortcut-mute">Toggle Mute</label>
        <input
          id="shortcut-mute"
          type="text"
          value={config.toggleMute}
          onChange={(e) => update("toggleMute", e.target.value)}
          placeholder="e.g. CmdOrCtrl+Shift+M"
        />
      </div>
      <div className="shortcut-row">
        <label htmlFor="shortcut-deafen">Toggle Deafen</label>
        <input
          id="shortcut-deafen"
          type="text"
          value={config.toggleDeafen}
          onChange={(e) => update("toggleDeafen", e.target.value)}
          placeholder="e.g. CmdOrCtrl+Shift+D"
        />
      </div>
      <div className="shortcut-row">
        <label htmlFor="shortcut-ptt">Push-to-Talk</label>
        <input
          id="shortcut-ptt"
          type="text"
          value={config.pushToTalk ?? ""}
          onChange={(e) => update("pushToTalk", e.target.value)}
          placeholder="Not set (type a key combo)"
        />
      </div>
    </div>
  );
}
