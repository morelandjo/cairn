import { describe, it, expect, afterAll } from "vitest";
import { buildApp } from "./index.js";

describe("SFU health endpoint", () => {
  const app = buildApp();

  afterAll(async () => {
    await app.close();
  });

  it("returns healthy status", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/health",
    });

    expect(response.statusCode).toBe(200);

    const body = JSON.parse(response.body);
    expect(body.status).toBe("healthy");
    expect(body.version).toBe("0.1.0");
    expect(body.services.mediasoup.status).toBe("up");
  });
});
