import { describe, it, expect, beforeAll } from "vitest";
import sodium from "libsodium-wrappers-sumo";
import {
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
} from "../keys.js";
import { x3dhInitiate, x3dhRespond } from "../x3dh.js";
import { DoubleRatchet } from "../ratchet.js";
import { encryptMessage, decryptMessage } from "../encrypt.js";
import type { KeyBundle } from "../../types.js";

beforeAll(async () => {
  await sodium.ready;
});

/**
 * Helper: set up X3DH and initialize ratchets for Alice and Bob.
 */
async function setupSession(): Promise<{
  alice: DoubleRatchet;
  bob: DoubleRatchet;
}> {
  const aliceIdentity = await generateIdentityKeyPair();
  const bobIdentity = await generateIdentityKeyPair();
  const bobSignedPreKey = await generateSignedPreKey(bobIdentity, 1);
  const bobOtpk = await generateOneTimePreKeys(1, 0);

  const bobBundle: KeyBundle = {
    identityKey: bobIdentity.publicKey,
    signedPreKey: bobSignedPreKey.publicKey,
    signedPreKeySignature: bobSignedPreKey.signature,
    signedPreKeyId: bobSignedPreKey.keyId,
    oneTimePreKey: bobOtpk[0]!.publicKey,
    oneTimePreKeyId: bobOtpk[0]!.keyId,
  };

  const { sharedSecret: aliceSecret, ephemeralPublicKey } =
    await x3dhInitiate(aliceIdentity, bobBundle);

  const bobSecret = await x3dhRespond(
    bobIdentity,
    bobSignedPreKey.privateKey,
    bobOtpk[0]!.privateKey,
    aliceIdentity.publicKey,
    ephemeralPublicKey,
  );

  const alice = await DoubleRatchet.initAsAlice(aliceSecret, bobSignedPreKey.publicKey);
  const bob = await DoubleRatchet.initAsBob(bobSecret, {
    publicKey: bobSignedPreKey.publicKey,
    privateKey: bobSignedPreKey.privateKey,
  });

  return { alice, bob };
}

describe("encryptMessage / decryptMessage", () => {
  it("encrypts and decrypts a string message round-trip", async () => {
    const { alice, bob } = await setupSession();

    const payload = await encryptMessage(alice, "Hello, encrypted world!");
    const decrypted = await decryptMessage(bob, payload);

    expect(new TextDecoder().decode(decrypted)).toBe("Hello, encrypted world!");
  });

  it("encrypts and decrypts a Uint8Array message round-trip", async () => {
    const { alice, bob } = await setupSession();

    const binary = new Uint8Array([0xff, 0x00, 0xab, 0xcd, 0xef]);
    const payload = await encryptMessage(alice, binary);
    const decrypted = await decryptMessage(bob, payload);

    expect(sodium.to_hex(decrypted)).toBe(sodium.to_hex(binary));
  });

  it("produces an EncryptedPayload with correct structure", async () => {
    const { alice } = await setupSession();

    const payload = await encryptMessage(alice, "Test message");

    expect(payload.header).toBeDefined();
    expect(payload.header.dhPublicKey).toBeInstanceOf(Uint8Array);
    expect(payload.header.dhPublicKey.length).toBe(32);
    expect(typeof payload.header.previousChainLength).toBe("number");
    expect(typeof payload.header.messageNumber).toBe("number");
    expect(payload.ciphertext).toBeInstanceOf(Uint8Array);
    expect(payload.nonce).toBeInstanceOf(Uint8Array);
    expect(payload.nonce.length).toBe(sodium.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES);
  });

  it("ciphertext differs from plaintext", async () => {
    const { alice } = await setupSession();

    const plaintext = "Do not read this";
    const payload = await encryptMessage(alice, plaintext);

    // The ciphertext should not contain the plaintext
    const ciphertextStr = new TextDecoder().decode(payload.ciphertext);
    expect(ciphertextStr).not.toContain(plaintext);
  });

  it("supports bidirectional encrypted conversation", async () => {
    const { alice, bob } = await setupSession();

    // Alice -> Bob
    const p1 = await encryptMessage(alice, "Hey Bob");
    const d1 = await decryptMessage(bob, p1);
    expect(new TextDecoder().decode(d1)).toBe("Hey Bob");

    // Bob -> Alice
    const p2 = await encryptMessage(bob, "Hey Alice");
    const d2 = await decryptMessage(alice, p2);
    expect(new TextDecoder().decode(d2)).toBe("Hey Alice");
  });

  it("each encryption produces different ciphertext for the same plaintext", async () => {
    const { alice } = await setupSession();

    const p1 = await encryptMessage(alice, "Same message");
    const p2 = await encryptMessage(alice, "Same message");

    // Different nonces and advancing chain keys mean different ciphertext
    expect(sodium.to_hex(p1.ciphertext)).not.toBe(sodium.to_hex(p2.ciphertext));
    expect(sodium.to_hex(p1.nonce)).not.toBe(sodium.to_hex(p2.nonce));
  });
});
