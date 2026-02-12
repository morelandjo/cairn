/**
 * HTTP client — thin wrapper around @cairn/proto ApiClient.
 * Maintains backward-compatible configureClient() and apiFetch() interfaces.
 */

import { ApiClient } from "@cairn/proto";

export const client = new ApiClient();

/** Wire up auth store functions so the client can read/write tokens. */
export function configureClient(opts: {
  getAccessToken: () => string | null;
  getRefreshToken: () => string | null;
  setTokens: (access: string, refresh: string) => void;
  onAuthFailure: () => void;
}) {
  client.configure({
    getAccessToken: opts.getAccessToken,
    getRefreshToken: opts.getRefreshToken,
    setTokens: opts.setTokens,
    onAuthFailure: opts.onAuthFailure,
  });
}

export function apiFetch<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  return client.fetch<T>(path, {
    method: options.method,
    headers: options.headers as Record<string, string> | undefined,
    body: options.body as string | FormData | undefined,
  });
}
