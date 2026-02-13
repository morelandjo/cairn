import { describe, it, expect } from "vitest";
import {
  deriveVoiceKey,
  encryptFrame,
  decryptFrame,
} from "./voiceEncryption.js";

describe("voiceEncryption", () => {
  const testEpochSecret = new Uint8Array(32);
  testEpochSecret.fill(42);

  describe("deriveVoiceKey", () => {
    it("derives a CryptoKey from epoch secret", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      expect(key).toBeDefined();
      expect(key.algorithm).toBeDefined();
    });

    it("derives deterministic keys", async () => {
      const key1 = await deriveVoiceKey(testEpochSecret);
      const key2 = await deriveVoiceKey(testEpochSecret);
      // Can't directly compare CryptoKeys, but both should work
      const data = new Uint8Array([1, 2, 3, 4, 5]);
      const encrypted = await encryptFrame(key1, data);
      const decrypted = await decryptFrame(key2, encrypted);
      expect(decrypted).toEqual(data);
    });

    it("different secrets produce different keys", async () => {
      const secret2 = new Uint8Array(32);
      secret2.fill(99);
      const key1 = await deriveVoiceKey(testEpochSecret);
      const key2 = await deriveVoiceKey(secret2);

      const data = new Uint8Array([1, 2, 3, 4, 5]);
      const encrypted = await encryptFrame(key1, data);

      // Decrypting with wrong key should fail
      await expect(decryptFrame(key2, encrypted)).rejects.toThrow();
    });
  });

  describe("encryptFrame / decryptFrame", () => {
    it("round-trips data", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      const original = new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80]);

      const encrypted = await encryptFrame(key, original);
      expect(encrypted.length).toBeGreaterThan(original.length);

      const decrypted = await decryptFrame(key, encrypted);
      expect(decrypted).toEqual(original);
    });

    it("produces different ciphertexts for same plaintext (unique IV)", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      const data = new Uint8Array([1, 2, 3]);

      const enc1 = await encryptFrame(key, data);
      const enc2 = await encryptFrame(key, data);

      // IVs should differ
      const iv1 = enc1.slice(0, 12);
      const iv2 = enc2.slice(0, 12);
      expect(iv1).not.toEqual(iv2);
    });

    it("rejects truncated frames", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      const tooShort = new Uint8Array(20); // Less than IV + tag

      await expect(decryptFrame(key, tooShort)).rejects.toThrow();
    });

    it("handles empty payload", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      const empty = new Uint8Array(0);

      const encrypted = await encryptFrame(key, empty);
      const decrypted = await decryptFrame(key, encrypted);
      expect(decrypted).toEqual(empty);
    });

    it("handles large frames", async () => {
      const key = await deriveVoiceKey(testEpochSecret);
      const large = new Uint8Array(4096);
      for (let i = 0; i < large.length; i++) {
        large[i] = i % 256;
      }

      const encrypted = await encryptFrame(key, large);
      const decrypted = await decryptFrame(key, encrypted);
      expect(decrypted).toEqual(large);
    });
  });
});
