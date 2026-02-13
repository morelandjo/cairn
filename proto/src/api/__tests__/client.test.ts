import { describe, it, expect, vi, beforeEach } from "vitest";
import { ApiClient } from "../client.js";
import type { ApiTransport, ApiResponse } from "../transport.js";

function mockResponse(
  status: number,
  body: unknown,
  ok?: boolean,
): ApiResponse {
  return {
    ok: ok ?? (status >= 200 && status < 300),
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

function createMockTransport() {
  const request = vi.fn<ApiTransport["request"]>();
  const transport: ApiTransport = { request };
  return { transport, request };
}

describe("ApiClient", () => {
  let mock: ReturnType<typeof createMockTransport>;
  let client: ApiClient;

  beforeEach(() => {
    mock = createMockTransport();
    client = new ApiClient({
      baseUrl: "https://example.com",
      transport: mock.transport,
    });
  });

  it("makes GET requests with correct URL", async () => {
    mock.request.mockResolvedValueOnce(
      mockResponse(200, { users: [] }),
    );

    const result = await client.fetch("/api/v1/users");
    expect(result).toEqual({ users: [] });
    expect(mock.request).toHaveBeenCalledWith(
      "https://example.com/api/v1/users",
      expect.objectContaining({
        headers: expect.objectContaining({
          "Content-Type": "application/json",
        }),
      }),
    );
  });

  it("makes POST requests with body", async () => {
    mock.request.mockResolvedValueOnce(
      mockResponse(201, { user: { id: "1" } }),
    );

    await client.fetch("/api/v1/auth/register", {
      method: "POST",
      body: JSON.stringify({ username: "test" }),
    });

    expect(mock.request).toHaveBeenCalledWith(
      "https://example.com/api/v1/auth/register",
      expect.objectContaining({
        method: "POST",
        body: '{"username":"test"}',
      }),
    );
  });

  it("includes Bearer token when configured", async () => {
    client.configure({ getAccessToken: () => "tok_123" });
    mock.request.mockResolvedValueOnce(mockResponse(200, { ok: true }));

    await client.fetch("/api/v1/me");

    expect(mock.request).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer tok_123",
        }),
      }),
    );
  });

  it("throws on non-ok response", async () => {
    mock.request.mockResolvedValueOnce(
      mockResponse(404, "Not found", false),
    );

    await expect(client.fetch("/api/v1/missing")).rejects.toThrow(
      /API error 404/,
    );
  });

  it("auto-refreshes on 401 and retries", async () => {
    const setTokens = vi.fn();
    client.configure({
      getAccessToken: () => "expired_tok",
      getRefreshToken: () => "refresh_tok",
      setTokens,
    });

    // First request: 401
    mock.request.mockResolvedValueOnce(mockResponse(401, "Unauthorized", false));
    // Refresh request: success
    mock.request.mockResolvedValueOnce(
      mockResponse(200, {
        access_token: "new_access",
        refresh_token: "new_refresh",
      }),
    );
    // Retry: success
    mock.request.mockResolvedValueOnce(
      mockResponse(200, { data: "ok" }),
    );

    // Update getAccessToken to return new token after setTokens is called
    let currentToken = "expired_tok";
    client.configure({
      getAccessToken: () => currentToken,
      setTokens: (access, refresh) => {
        currentToken = access;
        setTokens(access, refresh);
      },
    });

    // Re-mock for the fresh sequence
    mock.request.mockReset();
    mock.request.mockResolvedValueOnce(mockResponse(401, "Unauthorized", false));
    mock.request.mockResolvedValueOnce(
      mockResponse(200, {
        access_token: "new_access",
        refresh_token: "new_refresh",
      }),
    );
    mock.request.mockResolvedValueOnce(mockResponse(200, { data: "ok" }));

    const result = await client.fetch("/api/v1/protected");
    expect(result).toEqual({ data: "ok" });
    expect(setTokens).toHaveBeenCalledWith("new_access", "new_refresh");
    expect(mock.request).toHaveBeenCalledTimes(3);
  });

  it("calls onAuthFailure when refresh fails", async () => {
    const onAuthFailure = vi.fn();
    client.configure({
      getAccessToken: () => "expired_tok",
      getRefreshToken: () => "bad_refresh",
      onAuthFailure,
    });

    // First: 401
    mock.request.mockResolvedValueOnce(mockResponse(401, "Unauthorized", false));
    // Refresh: fails
    mock.request.mockResolvedValueOnce(mockResponse(401, "Invalid", false));

    await expect(client.fetch("/api/v1/protected")).rejects.toThrow(
      "Authentication failed",
    );
    expect(onAuthFailure).toHaveBeenCalled();
  });

  it("deduplicates concurrent refresh requests", async () => {
    let tokenVersion = 0;
    client.configure({
      getAccessToken: () => (tokenVersion > 0 ? "new_tok" : "expired"),
      getRefreshToken: () => "refresh",
      setTokens: () => {
        tokenVersion++;
      },
    });

    // Both requests hit 401
    mock.request.mockResolvedValueOnce(mockResponse(401, "", false));
    mock.request.mockResolvedValueOnce(mockResponse(401, "", false));
    // Single refresh
    mock.request.mockResolvedValueOnce(
      mockResponse(200, {
        access_token: "new_tok",
        refresh_token: "new_refresh",
      }),
    );
    // Two retries
    mock.request.mockResolvedValueOnce(mockResponse(200, { a: 1 }));
    mock.request.mockResolvedValueOnce(mockResponse(200, { b: 2 }));

    const [r1, r2] = await Promise.all([
      client.fetch("/api/v1/a"),
      client.fetch("/api/v1/b"),
    ]);

    expect(r1).toEqual({ a: 1 });
    expect(r2).toEqual({ b: 2 });
    // Should have: 2 original + 1 refresh + 2 retries = 5
    expect(mock.request.mock.calls.length).toBe(5);
  });

  it("works with empty baseUrl (relative URLs)", async () => {
    const relClient = new ApiClient({ transport: mock.transport });
    mock.request.mockResolvedValueOnce(mockResponse(200, { ok: true }));

    await relClient.fetch("/api/v1/health");

    expect(mock.request).toHaveBeenCalledWith(
      "/api/v1/health",
      expect.any(Object),
    );
  });
});
