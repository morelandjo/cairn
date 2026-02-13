import { describe, it, expect } from "vitest";
import { exportKeys, importKeys } from "../backup.js";
import type { KeyBackupPayload } from "../backup.js";
import { ensureSodium } from "../../crypto/index.js";

describe("Key Backup", () => {
  const passphrase = "correct-horse-battery-staple";

  it("round-trips a key backup", async () => {
    const s = await ensureSodium();

    const payload: KeyBackupPayload = {
      identityKeyPair: {
        publicKey: s.to_base64(s.randombytes_buf(32)),
        privateKey: s.to_base64(s.randombytes_buf(64)),
      },
      signedPreKey: {
        keyId: 1,
        publicKey: s.to_base64(s.randombytes_buf(32)),
        privateKey: s.to_base64(s.randombytes_buf(32)),
        signature: s.to_base64(s.randombytes_buf(64)),
        timestamp: Date.now(),
      },
      oneTimePreKeys: [
        {
          keyId: 0,
          publicKey: s.to_base64(s.randombytes_buf(32)),
          privateKey: s.to_base64(s.randombytes_buf(32)),
        },
      ],
      mlsCredential: {
        identity: s.to_base64(s.randombytes_buf(32)),
        signingPublicKey: s.to_base64(s.randombytes_buf(32)),
        signingPrivateKey: s.to_base64(s.randombytes_buf(32)),
      },
    };

    const encrypted = await exportKeys(payload, passphrase);
    expect(encrypted).toBeInstanceOf(Uint8Array);
    expect(encrypted.length).toBeGreaterThan(100);

    const restored = await importKeys(encrypted, passphrase);
    expect(restored).toEqual(payload);
  });

  it("rejects wrong passphrase", async () => {
    const payload: KeyBackupPayload = {
      identityKeyPair: {
        publicKey: "AAAA",
        privateKey: "BBBB",
      },
    };

    const encrypted = await exportKeys(payload, passphrase);

    await expect(importKeys(encrypted, "wrong-passphrase")).rejects.toThrow();
  });

  it("rejects truncated data", async () => {
    const payload: KeyBackupPayload = { identityKeyPair: { publicKey: "A", privateKey: "B" } };
    const encrypted = await exportKeys(payload, passphrase);

    // Truncate to just the header
    const truncated = encrypted.slice(0, 10);
    await expect(importKeys(truncated, passphrase)).rejects.toThrow("too short");
  });

  it("rejects tampered data", async () => {
    const payload: KeyBackupPayload = { identityKeyPair: { publicKey: "A", privateKey: "B" } };
    const encrypted = await exportKeys(payload, passphrase);

    // Flip a byte in the ciphertext
    const tampered = new Uint8Array(encrypted);
    tampered[tampered.length - 1] ^= 0xff;

    await expect(importKeys(tampered, passphrase)).rejects.toThrow();
  });

  it("rejects unsupported version", async () => {
    const payload: KeyBackupPayload = { identityKeyPair: { publicKey: "A", privateKey: "B" } };
    const encrypted = await exportKeys(payload, passphrase);

    // Change version byte
    const modified = new Uint8Array(encrypted);
    modified[0] = 99;

    await expect(importKeys(modified, passphrase)).rejects.toThrow("Unsupported backup version");
  });

  it("produces different ciphertext each time (unique salt/nonce)", async () => {
    const payload: KeyBackupPayload = { identityKeyPair: { publicKey: "A", privateKey: "B" } };

    const enc1 = await exportKeys(payload, passphrase);
    const enc2 = await exportKeys(payload, passphrase);

    // Same payload and passphrase should produce different output
    expect(enc1).not.toEqual(enc2);
  });

  it("handles empty payload", async () => {
    const payload: KeyBackupPayload = {};
    const encrypted = await exportKeys(payload, passphrase);
    const restored = await importKeys(encrypted, passphrase);
    expect(restored).toEqual({});
  });

  it("preserves custom fields in payload", async () => {
    const payload: KeyBackupPayload = {
      customField: "hello",
      nestedObject: { a: 1, b: [2, 3] },
    };

    const encrypted = await exportKeys(payload, passphrase);
    const restored = await importKeys(encrypted, passphrase);
    expect(restored).toEqual(payload);
  });
});
