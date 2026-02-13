/**
 * Transport abstraction for API requests.
 * Allows swapping fetch for native HTTP clients (Tauri, React Native, etc.).
 */

export interface ApiResponse {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
  text(): Promise<string>;
}

export interface ApiTransport {
  request(
    url: string,
    options: {
      method?: string;
      headers?: Record<string, string>;
      body?: string | FormData;
    },
  ): Promise<ApiResponse>;
}

/**
 * Default transport using global `fetch`.
 * Works in browsers, Node.js 18+, Deno, Bun, and Tauri webviews.
 */
export class FetchTransport implements ApiTransport {
  async request(
    url: string,
    options: {
      method?: string;
      headers?: Record<string, string>;
      body?: string | FormData;
    },
  ): Promise<ApiResponse> {
    const res = await fetch(url, {
      method: options.method,
      headers: options.headers,
      body: options.body,
    });
    return {
      ok: res.ok,
      status: res.status,
      json: () => res.json(),
      text: () => res.text(),
    };
  }
}
