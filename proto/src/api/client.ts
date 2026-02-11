/**
 * Platform-agnostic API client with Bearer auth and auto-refresh on 401.
 */

import type { ApiTransport } from "./transport.js";
import { FetchTransport } from "./transport.js";

export interface ApiClientOptions {
  baseUrl?: string;
  transport?: ApiTransport;
  getAccessToken?: () => string | null;
  getRefreshToken?: () => string | null;
  setTokens?: (access: string, refresh: string) => void;
  onAuthFailure?: () => void;
}

export class ApiClient {
  #baseUrl: string;
  #transport: ApiTransport;
  #getAccessToken: () => string | null;
  #getRefreshToken: () => string | null;
  #setTokens: (access: string, refresh: string) => void;
  #onAuthFailure: () => void;
  #isRefreshing = false;
  #refreshPromise: Promise<boolean> | null = null;

  constructor(options: ApiClientOptions = {}) {
    this.#baseUrl = options.baseUrl ?? "";
    this.#transport = options.transport ?? new FetchTransport();
    this.#getAccessToken = options.getAccessToken ?? (() => null);
    this.#getRefreshToken = options.getRefreshToken ?? (() => null);
    this.#setTokens = options.setTokens ?? (() => {});
    this.#onAuthFailure = options.onAuthFailure ?? (() => {});
  }

  configure(options: Partial<ApiClientOptions>): void {
    if (options.baseUrl !== undefined) this.#baseUrl = options.baseUrl;
    if (options.transport !== undefined) this.#transport = options.transport;
    if (options.getAccessToken !== undefined)
      this.#getAccessToken = options.getAccessToken;
    if (options.getRefreshToken !== undefined)
      this.#getRefreshToken = options.getRefreshToken;
    if (options.setTokens !== undefined) this.#setTokens = options.setTokens;
    if (options.onAuthFailure !== undefined)
      this.#onAuthFailure = options.onAuthFailure;
  }

  async #tryRefresh(): Promise<boolean> {
    if (this.#isRefreshing && this.#refreshPromise) {
      return this.#refreshPromise;
    }
    this.#isRefreshing = true;
    this.#refreshPromise = (async () => {
      try {
        const rt = this.#getRefreshToken();
        if (!rt) return false;
        const res = await this.#transport.request(
          `${this.#baseUrl}/api/v1/auth/refresh`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ refresh_token: rt }),
          },
        );
        if (!res.ok) return false;
        const data = (await res.json()) as {
          access_token: string;
          refresh_token: string;
        };
        this.#setTokens(data.access_token, data.refresh_token);
        return true;
      } catch {
        return false;
      } finally {
        this.#isRefreshing = false;
        this.#refreshPromise = null;
      }
    })();
    return this.#refreshPromise;
  }

  #buildHeaders(
    extraHeaders?: Record<string, string>,
    body?: string | FormData,
  ): Record<string, string> {
    const headers: Record<string, string> = { ...extraHeaders };
    const token = this.#getAccessToken();
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }
    if (!headers["Content-Type"] && !(body instanceof FormData)) {
      headers["Content-Type"] = "application/json";
    }
    return headers;
  }

  async fetch<T>(
    path: string,
    options: {
      method?: string;
      headers?: Record<string, string>;
      body?: string | FormData;
    } = {},
  ): Promise<T> {
    const url = `${this.#baseUrl}${path}`;
    const headers = this.#buildHeaders(options.headers, options.body);

    let res = await this.#transport.request(url, {
      ...options,
      headers,
    });

    if (res.status === 401 && this.#getAccessToken()) {
      const refreshed = await this.#tryRefresh();
      if (refreshed) {
        const newHeaders = this.#buildHeaders(options.headers, options.body);
        res = await this.#transport.request(url, {
          ...options,
          headers: newHeaders,
        });
      } else {
        this.#onAuthFailure();
        throw new Error("Authentication failed");
      }
    }

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`API error ${res.status}: ${body}`);
    }

    return (await res.json()) as T;
  }
}

/** Singleton default client instance for convenience. */
export const apiClient = new ApiClient();
