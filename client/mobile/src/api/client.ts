/**
 * HTTP client — wraps @murmuring/proto ApiClient with absolute base URL.
 */

import { ApiClient } from "@murmuring/proto";
import { getApiBaseUrl } from "../lib/config";

export const client = new ApiClient({ baseUrl: getApiBaseUrl() });

/** Wire up auth store functions so the client can read/write tokens. */
export function configureClient(opts: {
  getAccessToken: () => string | null;
  getRefreshToken: () => string | null;
  setTokens: (access: string, refresh: string) => void;
  onAuthFailure: () => void;
}) {
  client.configure({
    baseUrl: getApiBaseUrl(),
    getAccessToken: opts.getAccessToken,
    getRefreshToken: opts.getRefreshToken,
    setTokens: opts.setTokens,
    onAuthFailure: opts.onAuthFailure,
  });
}
