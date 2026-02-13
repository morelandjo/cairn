import { describe, it, expect, beforeAll } from "vitest";
import fs from "fs";
import path from "path";
import { initSync } from "../../../mls-wasm/pkg/mls_wasm.js";
import { MlsClient } from "../client.js";
import { ensureSodium, generateIdentityKeyPair } from "../../crypto/index.js";

let client: MlsClient;

beforeAll(() => {
  const wasmPath = path.resolve(
    __dirname,
    "../../../mls-wasm/pkg/mls_wasm_bg.wasm",
  );
  const wasmBytes = fs.readFileSync(wasmPath);

  client = new MlsClient();
  client.init(wasmBytes);
});

describe("MLS credential creation", () => {
  it("creates a credential from an Ed25519 identity key", async () => {
    await ensureSodium();
    const identity = await generateIdentityKeyPair();

    const credential = client.createCredential(identity.publicKey);

    expect(credential.identity).toBeInstanceOf(Uint8Array);
    expect(credential.identity).toHaveLength(32);
    expect(credential.signingPublicKey).toBeInstanceOf(Uint8Array);
    expect(credential.signingPublicKey).toHaveLength(32);
    expect(credential.signingPrivateKey).toBeInstanceOf(Uint8Array);
    expect(credential.signingPrivateKey).toHaveLength(32);

    // Identity should match the input public key
    expect(credential.identity).toEqual(identity.publicKey);

    // Signing key should be different from identity key (freshly generated)
    expect(credential.signingPublicKey).not.toEqual(identity.publicKey);
  });

  it("generates unique signing keys each time", async () => {
    await ensureSodium();
    const identity = await generateIdentityKeyPair();

    const cred1 = client.createCredential(identity.publicKey);
    const cred2 = client.createCredential(identity.publicKey);

    expect(cred1.signingPublicKey).not.toEqual(cred2.signingPublicKey);
    expect(cred1.signingPrivateKey).not.toEqual(cred2.signingPrivateKey);
  });

  it("rejects invalid identity key size", () => {
    expect(() => client.createCredential(new Uint8Array(16))).toThrow(
      "32 bytes",
    );
    expect(() => client.createCredential(new Uint8Array(64))).toThrow(
      "32 bytes",
    );
  });
});

describe("MLS signing key import", () => {
  it("imports an existing Ed25519 identity key pair (64-byte libsodium format)", async () => {
    await ensureSodium();
    const identity = await generateIdentityKeyPair();

    // libsodium privateKey is 64 bytes (seed || publicKey)
    expect(identity.privateKey).toHaveLength(64);

    const credential = client.importSigningKey(
      identity.publicKey,
      identity.privateKey,
      identity.publicKey,
    );

    expect(credential.identity).toEqual(identity.publicKey);
    expect(credential.signingPublicKey).toEqual(identity.publicKey);
    // Private key should be 32-byte seed (extracted from 64-byte libsodium key)
    expect(credential.signingPrivateKey).toHaveLength(32);
    expect(credential.signingPrivateKey).toEqual(
      identity.privateKey.slice(0, 32),
    );
  });

  it("imports a 32-byte raw seed", async () => {
    await ensureSodium();
    const identity = await generateIdentityKeyPair();
    const seed = identity.privateKey.slice(0, 32);

    const credential = client.importSigningKey(
      identity.publicKey,
      seed,
      identity.publicKey,
    );

    expect(credential.signingPrivateKey).toEqual(seed);
    expect(credential.signingPublicKey).toEqual(identity.publicKey);
  });

  it("rejects invalid key sizes", () => {
    const validKey = new Uint8Array(32);

    expect(() =>
      client.importSigningKey(new Uint8Array(16), validKey, validKey),
    ).toThrow("identity public key must be 32 bytes");

    expect(() =>
      client.importSigningKey(validKey, new Uint8Array(48), validKey),
    ).toThrow("32 or 64 bytes");

    expect(() =>
      client.importSigningKey(validKey, validKey, new Uint8Array(16)),
    ).toThrow("signing public key must be 32 bytes");
  });

  it("preserves credential identity correctly", async () => {
    await ensureSodium();
    const identity = await generateIdentityKeyPair();

    const credential = client.importSigningKey(
      identity.publicKey,
      identity.privateKey,
      identity.publicKey,
    );

    // The credential identity is the user's Ed25519 public key
    expect(credential.identity).toEqual(identity.publicKey);
  });
});

describe("MlsClient initialization", () => {
  it("throws if used before init()", () => {
    const uninitClient = new MlsClient();
    expect(() => uninitClient.createCredential(new Uint8Array(32))).toThrow(
      "not initialized",
    );
  });
});
