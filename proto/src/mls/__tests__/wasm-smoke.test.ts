import { describe, it, expect, beforeAll } from "vitest";
import fs from "fs";
import path from "path";
import { initSync, mls_version, supported_ciphersuites } from "../../../mls-wasm/pkg/mls_wasm.js";

beforeAll(() => {
  const wasmPath = path.resolve(__dirname, "../../../mls-wasm/pkg/mls_wasm_bg.wasm");
  const wasmBytes = fs.readFileSync(wasmPath);
  initSync({ module: wasmBytes });
});

describe("MLS WASM smoke test", () => {
  it("returns protocol version", () => {
    const version = mls_version();
    expect(version).toBe("RFC9420-v1");
  });

  it("returns supported ciphersuites", () => {
    const raw = supported_ciphersuites();
    const suites = JSON.parse(raw);
    expect(Array.isArray(suites)).toBe(true);
    expect(suites).toHaveLength(1);
    expect(suites[0].name).toBe("MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519");
    expect(suites[0].value).toBe(1);
  });
});
