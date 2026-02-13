/**
 * Desktop bridge — detects Tauri environment and provides typed invoke() wrappers.
 * No-ops gracefully when running in a regular browser.
 */

/** Whether we're running inside a Tauri webview. */
export const isTauri: boolean =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

// Tauri's invoke function, loaded dynamically
type InvokeFn = (cmd: string, args?: Record<string, unknown>) => Promise<unknown>;
let invokeFn: InvokeFn | null = null;

async function getInvoke(): Promise<InvokeFn | null> {
  if (!isTauri) return null;
  if (invokeFn) return invokeFn;
  try {
    const mod = await import("@tauri-apps/api/core");
    invokeFn = mod.invoke;
    return invokeFn;
  } catch {
    return null;
  }
}

/** Send a native OS notification (privacy-respecting — no message content). */
export async function sendNotification(
  title: string,
  body: string,
): Promise<void> {
  const invoke = await getInvoke();
  if (invoke) {
    await invoke("send_notification", { title, body });
  }
}

/** Listen for tray "mute notifications" toggle. */
export async function onTrayMuteNotifications(
  callback: () => void,
): Promise<() => void> {
  if (!isTauri) return () => {};
  try {
    const { listen } = await import("@tauri-apps/api/event");
    const unlisten = await listen("tray-mute-notifications", () => callback());
    return unlisten;
  } catch {
    return () => {};
  }
}

/** Listen for deep link navigation events. */
export async function onDeepLink(
  callback: (url: string) => void,
): Promise<() => void> {
  if (!isTauri) return () => {};
  try {
    const { listen } = await import("@tauri-apps/api/event");
    const unlisten = await listen<string>("deep-link", (event) => {
      callback(event.payload);
    });
    return unlisten;
  } catch {
    return () => {};
  }
}
