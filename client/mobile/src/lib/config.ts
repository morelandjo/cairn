/**
 * Server URL configuration for mobile.
 * Mobile needs absolute URLs since it can't use relative paths.
 * Persists server URL to secure storage.
 */

import { loadKeySync, storeKeySync } from "./keyStorage";

let serverUrl: string = loadKeySync("server_url") || "";

export function getServerUrl(): string {
  return serverUrl;
}

export function setServerUrl(url: string): void {
  serverUrl = url.replace(/\/$/, "");
  storeKeySync("server_url", serverUrl);
}

export function hasServerUrl(): boolean {
  return serverUrl.length > 0;
}

export function getApiBaseUrl(): string {
  return serverUrl;
}

export function getWsUrl(): string {
  const url = new URL(serverUrl);
  const protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${url.host}`;
}
