import { describe, it, expect, beforeAll } from "vitest";
import sodium from "libsodium-wrappers-sumo";
import {
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
} from "../keys.js";

beforeAll(async () => {
  await sodium.ready;
});

describe("generateIdentityKeyPair", () => {
  it("produces an Ed25519 key pair with correct lengths", async () => {
    const kp = await generateIdentityKeyPair();
    expect(kp.keyType).toBe("ed25519");
    expect(kp.publicKey).toBeInstanceOf(Uint8Array);
    expect(kp.privateKey).toBeInstanceOf(Uint8Array);
    expect(kp.publicKey.length).toBe(sodium.crypto_sign_PUBLICKEYBYTES);
    expect(kp.privateKey.length).toBe(sodium.crypto_sign_SECRETKEYBYTES);
  });

  it("produces unique key pairs each time", async () => {
    const kp1 = await generateIdentityKeyPair();
    const kp2 = await generateIdentityKeyPair();
    expect(sodium.to_hex(kp1.publicKey)).not.toBe(sodium.to_hex(kp2.publicKey));
  });

  it("produces a valid signing key pair", async () => {
    const kp = await generateIdentityKeyPair();
    const message = new Uint8Array([1, 2, 3, 4, 5]);
    const signature = sodium.crypto_sign_detached(message, kp.privateKey);
    expect(sodium.crypto_sign_verify_detached(signature, message, kp.publicKey)).toBe(true);
  });
});

describe("generateSignedPreKey", () => {
  it("produces an X25519 key pair with a valid signature", async () => {
    const identityKp = await generateIdentityKeyPair();
    const spk = await generateSignedPreKey(identityKp, 1);

    expect(spk.keyId).toBe(1);
    expect(spk.publicKey).toBeInstanceOf(Uint8Array);
    expect(spk.privateKey).toBeInstanceOf(Uint8Array);
    expect(spk.signature).toBeInstanceOf(Uint8Array);
    expect(spk.publicKey.length).toBe(sodium.crypto_box_PUBLICKEYBYTES);
    expect(spk.privateKey.length).toBe(sodium.crypto_box_SECRETKEYBYTES);

    // Verify the signature over the public key
    const valid = sodium.crypto_sign_verify_detached(
      spk.signature,
      spk.publicKey,
      identityKp.publicKey,
    );
    expect(valid).toBe(true);
  });

  it("includes a timestamp", async () => {
    const identityKp = await generateIdentityKeyPair();
    const before = Date.now();
    const spk = await generateSignedPreKey(identityKp, 42);
    const after = Date.now();

    expect(spk.timestamp).toBeGreaterThanOrEqual(before);
    expect(spk.timestamp).toBeLessThanOrEqual(after);
  });
});

describe("generateOneTimePreKeys", () => {
  it("generates the requested number of key pairs", async () => {
    const keys = await generateOneTimePreKeys(5);
    expect(keys).toHaveLength(5);
  });

  it("assigns sequential key IDs starting from startId", async () => {
    const keys = await generateOneTimePreKeys(3, 10);
    expect(keys[0]!.keyId).toBe(10);
    expect(keys[1]!.keyId).toBe(11);
    expect(keys[2]!.keyId).toBe(12);
  });

  it("produces valid X25519 key pairs", async () => {
    const keys = await generateOneTimePreKeys(2);
    for (const key of keys) {
      expect(key.publicKey.length).toBe(sodium.crypto_box_PUBLICKEYBYTES);
      expect(key.privateKey.length).toBe(sodium.crypto_box_SECRETKEYBYTES);
    }
  });

  it("produces unique key pairs", async () => {
    const keys = await generateOneTimePreKeys(3);
    const hexKeys = keys.map((k) => sodium.to_hex(k.publicKey));
    const unique = new Set(hexKeys);
    expect(unique.size).toBe(3);
  });

  it("generates zero keys when count is zero", async () => {
    const keys = await generateOneTimePreKeys(0);
    expect(keys).toHaveLength(0);
  });
});
