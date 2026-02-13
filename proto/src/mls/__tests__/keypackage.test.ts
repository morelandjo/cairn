import { describe, it, expect, beforeAll } from "vitest";
import fs from "fs";
import path from "path";
import { MlsClient } from "../client.js";
import type { MlsCredential } from "../types.js";
import { ensureSodium, generateIdentityKeyPair } from "../../crypto/index.js";

let client: MlsClient;
let credential: MlsCredential;

beforeAll(async () => {
  const wasmPath = path.resolve(
    __dirname,
    "../../../mls-wasm/pkg/mls_wasm_bg.wasm",
  );
  const wasmBytes = fs.readFileSync(wasmPath);

  client = new MlsClient();
  client.init(wasmBytes);

  await ensureSodium();
  const identity = await generateIdentityKeyPair();
  credential = client.importSigningKey(
    identity.publicKey,
    identity.privateKey,
    identity.publicKey,
  );
});

describe("MLS KeyPackage generation", () => {
  it("generates a single KeyPackage", () => {
    const packages = client.generateKeyPackages(credential, 1);

    expect(packages).toHaveLength(1);
    expect(packages[0].keyPackageData).toBeInstanceOf(Uint8Array);
    expect(packages[0].keyPackageData.length).toBeGreaterThan(0);
    expect(packages[0].initPrivateKey).toBeInstanceOf(Uint8Array);
    expect(packages[0].initPrivateKey.length).toBeGreaterThan(0);
  });

  it("generates multiple unique KeyPackages", () => {
    const count = 5;
    const packages = client.generateKeyPackages(credential, count);

    expect(packages).toHaveLength(count);

    // Each KeyPackage should have unique data (different init keys)
    const dataSet = new Set(
      packages.map((p) => Buffer.from(p.keyPackageData).toString("hex")),
    );
    expect(dataSet.size).toBe(count);

    // Each init private key should be unique
    const keySet = new Set(
      packages.map((p) => Buffer.from(p.initPrivateKey).toString("hex")),
    );
    expect(keySet.size).toBe(count);
  });

  it("generates valid TLS-serialized KeyPackage data", () => {
    const packages = client.generateKeyPackages(credential, 1);
    const data = packages[0].keyPackageData;

    // TLS-serialized KeyPackage should be non-trivial (> 100 bytes)
    expect(data.length).toBeGreaterThan(100);
  });

  it("defaults to 50 KeyPackages", () => {
    const packages = client.generateKeyPackages(credential);
    expect(packages).toHaveLength(50);
  });
});
