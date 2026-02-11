import { describe, it, expect, beforeAll } from "vitest";
import sodium from "libsodium-wrappers-sumo";
import {
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
} from "../keys.js";
import { x3dhInitiate, x3dhRespond } from "../x3dh.js";
import type { KeyBundle } from "../../types.js";

beforeAll(async () => {
  await sodium.ready;
});

describe("X3DH key agreement", () => {
  it("both sides derive the same shared secret (with one-time pre-key)", async () => {
    // Generate Alice's keys
    const aliceIdentity = await generateIdentityKeyPair();

    // Generate Bob's keys
    const bobIdentity = await generateIdentityKeyPair();
    const bobSignedPreKey = await generateSignedPreKey(bobIdentity, 1);
    const bobOneTimePreKeys = await generateOneTimePreKeys(1, 0);

    // Bob publishes his key bundle
    const bobBundle: KeyBundle = {
      identityKey: bobIdentity.publicKey,
      signedPreKey: bobSignedPreKey.publicKey,
      signedPreKeySignature: bobSignedPreKey.signature,
      signedPreKeyId: bobSignedPreKey.keyId,
      oneTimePreKey: bobOneTimePreKeys[0]!.publicKey,
      oneTimePreKeyId: bobOneTimePreKeys[0]!.keyId,
    };

    // Alice initiates
    const { sharedSecret: aliceSecret, ephemeralPublicKey } =
      await x3dhInitiate(aliceIdentity, bobBundle);

    // Bob responds
    const bobSecret = await x3dhRespond(
      bobIdentity,
      bobSignedPreKey.privateKey,
      bobOneTimePreKeys[0]!.privateKey,
      aliceIdentity.publicKey,
      ephemeralPublicKey,
    );

    // Both should derive the same shared secret
    expect(sodium.to_hex(aliceSecret)).toBe(sodium.to_hex(bobSecret));
    expect(aliceSecret.length).toBe(32);
  });

  it("both sides derive the same shared secret (without one-time pre-key)", async () => {
    const aliceIdentity = await generateIdentityKeyPair();
    const bobIdentity = await generateIdentityKeyPair();
    const bobSignedPreKey = await generateSignedPreKey(bobIdentity, 1);

    const bobBundle: KeyBundle = {
      identityKey: bobIdentity.publicKey,
      signedPreKey: bobSignedPreKey.publicKey,
      signedPreKeySignature: bobSignedPreKey.signature,
      signedPreKeyId: bobSignedPreKey.keyId,
      // No one-time pre-key
    };

    const { sharedSecret: aliceSecret, ephemeralPublicKey } =
      await x3dhInitiate(aliceIdentity, bobBundle);

    const bobSecret = await x3dhRespond(
      bobIdentity,
      bobSignedPreKey.privateKey,
      null,
      aliceIdentity.publicKey,
      ephemeralPublicKey,
    );

    expect(sodium.to_hex(aliceSecret)).toBe(sodium.to_hex(bobSecret));
  });

  it("rejects an invalid signed pre-key signature", async () => {
    const aliceIdentity = await generateIdentityKeyPair();
    const bobIdentity = await generateIdentityKeyPair();
    const bobSignedPreKey = await generateSignedPreKey(bobIdentity, 1);

    // Tamper with the signature
    const badSignature = new Uint8Array(bobSignedPreKey.signature);
    badSignature[0] = (badSignature[0]! + 1) % 256;

    const bobBundle: KeyBundle = {
      identityKey: bobIdentity.publicKey,
      signedPreKey: bobSignedPreKey.publicKey,
      signedPreKeySignature: badSignature,
      signedPreKeyId: bobSignedPreKey.keyId,
    };

    await expect(x3dhInitiate(aliceIdentity, bobBundle)).rejects.toThrow(
      "Invalid signed pre-key signature",
    );
  });

  it("different key bundles produce different shared secrets", async () => {
    const aliceIdentity = await generateIdentityKeyPair();

    const bobIdentity1 = await generateIdentityKeyPair();
    const bobSpk1 = await generateSignedPreKey(bobIdentity1, 1);
    const bundle1: KeyBundle = {
      identityKey: bobIdentity1.publicKey,
      signedPreKey: bobSpk1.publicKey,
      signedPreKeySignature: bobSpk1.signature,
      signedPreKeyId: bobSpk1.keyId,
    };

    const bobIdentity2 = await generateIdentityKeyPair();
    const bobSpk2 = await generateSignedPreKey(bobIdentity2, 1);
    const bundle2: KeyBundle = {
      identityKey: bobIdentity2.publicKey,
      signedPreKey: bobSpk2.publicKey,
      signedPreKeySignature: bobSpk2.signature,
      signedPreKeyId: bobSpk2.keyId,
    };

    const { sharedSecret: secret1 } = await x3dhInitiate(aliceIdentity, bundle1);
    const { sharedSecret: secret2 } = await x3dhInitiate(aliceIdentity, bundle2);

    expect(sodium.to_hex(secret1)).not.toBe(sodium.to_hex(secret2));
  });

  it("produces a 32-byte shared secret", async () => {
    const aliceIdentity = await generateIdentityKeyPair();
    const bobIdentity = await generateIdentityKeyPair();
    const bobSpk = await generateSignedPreKey(bobIdentity, 1);

    const bundle: KeyBundle = {
      identityKey: bobIdentity.publicKey,
      signedPreKey: bobSpk.publicKey,
      signedPreKeySignature: bobSpk.signature,
      signedPreKeyId: bobSpk.keyId,
    };

    const { sharedSecret } = await x3dhInitiate(aliceIdentity, bundle);
    expect(sharedSecret.length).toBe(32);
  });
});
