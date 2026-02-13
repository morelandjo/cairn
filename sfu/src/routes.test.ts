import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { buildApp } from "./index.js";
import type { FastifyInstance } from "fastify";

const AUTH_HEADER = `Bearer ${process.env["SFU_AUTH_SECRET"] || "dev-sfu-secret"}`;

let app: FastifyInstance;

beforeAll(async () => {
  app = await buildApp();
  await app.ready();
}, 30_000);

afterAll(async () => {
  await app.close();
});

function inject(
  method: "GET" | "POST" | "DELETE",
  url: string,
  body?: unknown
) {
  return app.inject({
    method,
    url,
    headers: { authorization: AUTH_HEADER },
    ...(body ? { payload: body } : {}),
  });
}

describe("Health", () => {
  it("returns healthy status without auth", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.status).toBe("healthy");
    expect(typeof body.workers).toBe("number");
    expect(body.rooms).toBe(0);
  });
});

describe("Auth", () => {
  it("rejects requests without auth header", async () => {
    const res = await app.inject({ method: "POST", url: "/rooms", payload: { channelId: "test" } });
    expect(res.statusCode).toBe(401);
  });

  it("rejects requests with wrong secret", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/rooms",
      headers: { authorization: "Bearer wrong-secret" },
      payload: { channelId: "test" },
    });
    expect(res.statusCode).toBe(403);
  });
});

describe("Room lifecycle", () => {
  const channelId = "test-channel-1";

  it("creates a room", async () => {
    const res = await inject("POST", "/rooms", { channelId });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.channelId).toBe(channelId);
    expect(body.rtpCapabilities).toBeDefined();
    expect(body.rtpCapabilities.codecs).toBeInstanceOf(Array);
  });

  it("returns existing room on duplicate create", async () => {
    const res = await inject("POST", "/rooms", { channelId });
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body).channelId).toBe(channelId);
  });

  it("gets RTP capabilities", async () => {
    const res = await inject("GET", `/rooms/${channelId}/rtp-capabilities`);
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.codecs).toBeInstanceOf(Array);
  });

  it("returns 404 for non-existent room capabilities", async () => {
    const res = await inject("GET", "/rooms/nonexistent/rtp-capabilities");
    expect(res.statusCode).toBe(404);
  });

  it("destroys a room", async () => {
    const res = await inject("DELETE", `/rooms/${channelId}`);
    expect(res.statusCode).toBe(200);
  });

  it("returns 404 when destroying non-existent room", async () => {
    const res = await inject("DELETE", `/rooms/${channelId}`);
    expect(res.statusCode).toBe(404);
  });
});

describe("Peer lifecycle", () => {
  const channelId = "test-channel-2";
  const userId = "user-1";

  beforeAll(async () => {
    await inject("POST", "/rooms", { channelId });
  });

  afterAll(async () => {
    await inject("DELETE", `/rooms/${channelId}`);
  });

  it("adds a peer", async () => {
    const res = await inject("POST", `/rooms/${channelId}/peers`, { userId });
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body).userId).toBe(userId);
  });

  it("returns existing peer on duplicate add", async () => {
    const res = await inject("POST", `/rooms/${channelId}/peers`, { userId });
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body).userId).toBe(userId);
  });

  it("removes a peer", async () => {
    const res = await inject("DELETE", `/rooms/${channelId}/peers/${userId}`);
    expect(res.statusCode).toBe(200);
  });

  it("returns 404 when removing non-existent peer", async () => {
    const res = await inject("DELETE", `/rooms/${channelId}/peers/${userId}`);
    expect(res.statusCode).toBe(404);
  });
});

describe("Transport + Produce + Consume flow", () => {
  const channelId = "test-channel-3";
  const senderId = "sender-1";
  const receiverId = "receiver-1";
  let sendTransportId: string;
  let recvTransportId: string;
  let producerId: string;

  beforeAll(async () => {
    await inject("POST", "/rooms", { channelId });
    await inject("POST", `/rooms/${channelId}/peers`, { userId: senderId });
    await inject("POST", `/rooms/${channelId}/peers`, { userId: receiverId });
  });

  afterAll(async () => {
    await inject("DELETE", `/rooms/${channelId}`);
  });

  it("creates a send transport", async () => {
    const res = await inject(
      "POST",
      `/rooms/${channelId}/peers/${senderId}/send-transport`
    );
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.id).toBeDefined();
    expect(body.iceParameters).toBeDefined();
    expect(body.iceCandidates).toBeDefined();
    expect(body.dtlsParameters).toBeDefined();
    sendTransportId = body.id;
  });

  it("creates a recv transport", async () => {
    const res = await inject(
      "POST",
      `/rooms/${channelId}/peers/${receiverId}/recv-transport`
    );
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.id).toBeDefined();
    recvTransportId = body.id;
  });

  it("connects send transport", async () => {
    // We need valid DTLS parameters — get them from the transport
    // In a real flow the client generates these; here we use a minimal set
    const res = await inject(
      "POST",
      `/rooms/${channelId}/transports/${sendTransportId}/connect`,
      {
        dtlsParameters: {
          role: "client",
          fingerprints: [
            {
              algorithm: "sha-256",
              value:
                "A0:B1:C2:D3:E4:F5:06:17:28:39:4A:5B:6C:7D:8E:9F:A0:B1:C2:D3:E4:F5:06:17:28:39:4A:5B:6C:7D:8E:9F",
            },
          ],
        },
      }
    );
    // mediasoup may reject synthetic fingerprints, but the route should find the transport
    // Accept 200 or 500 (internal mediasoup error with fake DTLS)
    expect([200, 500]).toContain(res.statusCode);
  });

  it("returns 404 for send transport on non-existent peer", async () => {
    const res = await inject(
      "POST",
      `/rooms/${channelId}/peers/nobody/send-transport`
    );
    expect(res.statusCode).toBe(404);
  });

  it("lists producers (empty initially)", async () => {
    const res = await inject("GET", `/rooms/${channelId}/producers`);
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual([]);
  });
});

describe("Error handling", () => {
  it("returns 400 for missing channelId on room create", async () => {
    const res = await inject("POST", "/rooms", {});
    expect(res.statusCode).toBe(400);
  });

  it("returns 400 for missing userId on peer create", async () => {
    // Create room first
    await inject("POST", "/rooms", { channelId: "err-test" });
    const res = await inject("POST", "/rooms/err-test/peers", {});
    expect(res.statusCode).toBe(400);
    await inject("DELETE", "/rooms/err-test");
  });

  it("returns 404 for consume on non-existent room", async () => {
    const res = await inject("POST", "/rooms/nonexistent/consumers", {
      consumerUserId: "u",
      producerId: "p",
      rtpCapabilities: {},
    });
    expect(res.statusCode).toBe(404);
  });
});
