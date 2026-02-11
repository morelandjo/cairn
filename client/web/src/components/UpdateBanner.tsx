/**
 * Update banner — shown when a new desktop app version is available.
 * Only renders in Tauri environment.
 */

import { useEffect, useState } from "react";
import { isTauri } from "../lib/desktopBridge.ts";

export function UpdateBanner() {
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (!isTauri) return;

    let cancelled = false;

    async function checkUpdate() {
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        const version = (await invoke("check_for_update")) as string | null;
        if (!cancelled && version) {
          setUpdateVersion(version);
        }
      } catch {
        // silently ignore update check failures
      }
    }

    checkUpdate();
    // Check periodically (every 4 hours)
    const interval = setInterval(checkUpdate, 4 * 60 * 60 * 1000);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  if (!updateVersion || dismissed) return null;

  const handleRestart = async () => {
    try {
      const { relaunch } = await import("@tauri-apps/plugin-process");
      await relaunch();
    } catch {
      // fallback
    }
  };

  return (
    <div className="update-banner">
      <span>Update available: v{updateVersion}</span>
      <button onClick={handleRestart}>Restart to update</button>
      <button onClick={() => setDismissed(true)} className="dismiss">
        Dismiss
      </button>
    </div>
  );
}
