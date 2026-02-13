/**
 * Key storage abstraction — Web uses localStorage, Desktop uses OS keychain via Tauri invoke.
 */

import { isTauri } from "./desktopBridge.ts";

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

export async function storeKey(key: string, value: string): Promise<void> {
  const invoke = await getInvoke();
  if (invoke) {
    await invoke("keychain_store", { key, value });
  } else {
    localStorage.setItem(`murmur_${key}`, value);
  }
}

export async function loadKey(key: string): Promise<string | null> {
  const invoke = await getInvoke();
  if (invoke) {
    const result = (await invoke("keychain_load", { key })) as string | null;
    return result;
  }
  return localStorage.getItem(`murmur_${key}`);
}

export async function deleteKey(key: string): Promise<void> {
  const invoke = await getInvoke();
  if (invoke) {
    await invoke("keychain_delete", { key });
  } else {
    localStorage.removeItem(`murmur_${key}`);
  }
}

/** Synchronous load for contexts that can't await (e.g., store initialization). */
export function loadKeySync(key: string): string | null {
  // Keychain is async-only, so sync path always falls back to localStorage
  return localStorage.getItem(`murmur_${key}`);
}

/** Synchronous store for contexts that can't await. */
export function storeKeySync(key: string, value: string): void {
  localStorage.setItem(`murmur_${key}`, value);
  // Also persist to keychain asynchronously on desktop
  if (isTauri) {
    storeKey(key, value).catch(() => {});
  }
}

/** Synchronous delete for contexts that can't await. */
export function deleteKeySync(key: string): void {
  localStorage.removeItem(`murmur_${key}`);
  if (isTauri) {
    deleteKey(key).catch(() => {});
  }
}
