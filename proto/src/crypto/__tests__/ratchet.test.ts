import { describe, it, expect, beforeAll } from "vitest";
import sodium from "libsodium-wrappers-sumo";
import {
  generateIdentityKeyPair,
  generateSignedPreKey,
  generateOneTimePreKeys,
} from "../keys.js";
import { x3dhInitiate, x3dhRespond } from "../x3dh.js";
import { DoubleRatchet } from "../ratchet.js";
import type { KeyBundle } from "../../types.js";

beforeAll(async () => {
  await sodium.ready;
});

/**
 * Helper: perform X3DH and return initialized ratchets for Alice and Bob.
 */
async function setupRatchets(): Promise<{
  alice: DoubleRatchet;
  bob: DoubleRatchet;
}> {
  const aliceIdentity = await generateIdentityKeyPair();
  const bobIdentity = await generateIdentityKeyPair();
  const bobSignedPreKey = await generateSignedPreKey(bobIdentity, 1);
  const bobOneTimePreKeys = await generateOneTimePreKeys(1, 0);

  const bobBundle: KeyBundle = {
    identityKey: bobIdentity.publicKey,
    signedPreKey: bobSignedPreKey.publicKey,
    signedPreKeySignature: bobSignedPreKey.signature,
    signedPreKeyId: bobSignedPreKey.keyId,
    oneTimePreKey: bobOneTimePreKeys[0]!.publicKey,
    oneTimePreKeyId: bobOneTimePreKeys[0]!.keyId,
  };

  const { sharedSecret: aliceSecret, ephemeralPublicKey } =
    await x3dhInitiate(aliceIdentity, bobBundle);

  const bobSecret = await x3dhRespond(
    bobIdentity,
    bobSignedPreKey.privateKey,
    bobOneTimePreKeys[0]!.privateKey,
    aliceIdentity.publicKey,
    ephemeralPublicKey,
  );

  // Alice initializes as the sender
  const alice = await DoubleRatchet.initAsAlice(
    aliceSecret,
    bobSignedPreKey.publicKey,
  );

  // Bob initializes as the receiver
  const bob = await DoubleRatchet.initAsBob(bobSecret, {
    publicKey: bobSignedPreKey.publicKey,
    privateKey: bobSignedPreKey.privateKey,
  });

  return { alice, bob };
}

describe("DoubleRatchet", () => {
  it("encrypts and decrypts a single message (Alice -> Bob)", async () => {
    const { alice, bob } = await setupRatchets();

    const plaintext = new TextEncoder().encode("Hello, Bob!");
    const { header, ciphertext, nonce } = await alice.encrypt(plaintext);

    const decrypted = await bob.decrypt(header, ciphertext, nonce);
    expect(new TextDecoder().decode(decrypted)).toBe("Hello, Bob!");
  });

  it("encrypts and decrypts multiple messages in sequence", async () => {
    const { alice, bob } = await setupRatchets();

    for (let i = 0; i < 5; i++) {
      const plaintext = new TextEncoder().encode(`Message ${i}`);
      const { header, ciphertext, nonce } = await alice.encrypt(plaintext);
      const decrypted = await bob.decrypt(header, ciphertext, nonce);
      expect(new TextDecoder().decode(decrypted)).toBe(`Message ${i}`);
    }
  });

  it("supports bidirectional communication", async () => {
    const { alice, bob } = await setupRatchets();

    // Alice -> Bob
    const msg1 = new TextEncoder().encode("Hi Bob!");
    const enc1 = await alice.encrypt(msg1);
    const dec1 = await bob.decrypt(enc1.header, enc1.ciphertext, enc1.nonce);
    expect(new TextDecoder().decode(dec1)).toBe("Hi Bob!");

    // Bob -> Alice
    const msg2 = new TextEncoder().encode("Hi Alice!");
    const enc2 = await bob.encrypt(msg2);
    const dec2 = await alice.decrypt(enc2.header, enc2.ciphertext, enc2.nonce);
    expect(new TextDecoder().decode(dec2)).toBe("Hi Alice!");

    // Alice -> Bob again
    const msg3 = new TextEncoder().encode("How are you?");
    const enc3 = await alice.encrypt(msg3);
    const dec3 = await bob.decrypt(enc3.header, enc3.ciphertext, enc3.nonce);
    expect(new TextDecoder().decode(dec3)).toBe("How are you?");
  });

  it("handles out-of-order messages", async () => {
    const { alice, bob } = await setupRatchets();

    // Alice sends 3 messages
    const enc1 = await alice.encrypt(new TextEncoder().encode("Message 1"));
    const enc2 = await alice.encrypt(new TextEncoder().encode("Message 2"));
    const enc3 = await alice.encrypt(new TextEncoder().encode("Message 3"));

    // Bob receives them out of order: 3, 1, 2
    const dec3 = await bob.decrypt(enc3.header, enc3.ciphertext, enc3.nonce);
    expect(new TextDecoder().decode(dec3)).toBe("Message 3");

    const dec1 = await bob.decrypt(enc1.header, enc1.ciphertext, enc1.nonce);
    expect(new TextDecoder().decode(dec1)).toBe("Message 1");

    const dec2 = await bob.decrypt(enc2.header, enc2.ciphertext, enc2.nonce);
    expect(new TextDecoder().decode(dec2)).toBe("Message 2");
  });

  it("provides forward secrecy — old keys cannot decrypt new messages", async () => {
    const { alice, bob } = await setupRatchets();

    // Alice sends a message, Bob decrypts it
    const msg1 = new TextEncoder().encode("Secret message");
    const enc1 = await alice.encrypt(msg1);
    await bob.decrypt(enc1.header, enc1.ciphertext, enc1.nonce);

    // Forward secrecy: after the ratchet advances, old message keys
    // are deleted and cannot be used to decrypt already-consumed messages.
    // Send a second message from Alice
    const msg2 = new TextEncoder().encode("Second secret");
    const enc2 = await alice.encrypt(msg2);
    await bob.decrypt(enc2.header, enc2.ciphertext, enc2.nonce);

    // Try to decrypt message 1 again with the current bob state —
    // the message key was already consumed so it should fail
    await expect(async () => {
      await bob.decrypt(enc1.header, enc1.ciphertext, enc1.nonce);
    }).rejects.toThrow();
  });

  it("serializes and deserializes the ratchet state", async () => {
    const { alice, bob } = await setupRatchets();

    // Exchange a couple of messages
    const enc1 = await alice.encrypt(new TextEncoder().encode("First"));
    await bob.decrypt(enc1.header, enc1.ciphertext, enc1.nonce);

    const enc2 = await bob.encrypt(new TextEncoder().encode("Second"));
    await alice.decrypt(enc2.header, enc2.ciphertext, enc2.nonce);

    // Serialize both sides
    const aliceState = alice.serialize();
    const bobState = bob.serialize();

    // Deserialize
    const alice2 = DoubleRatchet.deserialize(aliceState);
    const bob2 = DoubleRatchet.deserialize(bobState);

    // Continue the conversation with deserialized ratchets
    const enc3 = await alice2.encrypt(new TextEncoder().encode("Third"));
    const dec3 = await bob2.decrypt(enc3.header, enc3.ciphertext, enc3.nonce);
    expect(new TextDecoder().decode(dec3)).toBe("Third");

    const enc4 = await bob2.encrypt(new TextEncoder().encode("Fourth"));
    const dec4 = await alice2.decrypt(enc4.header, enc4.ciphertext, enc4.nonce);
    expect(new TextDecoder().decode(dec4)).toBe("Fourth");
  });

  it("handles empty plaintext", async () => {
    const { alice, bob } = await setupRatchets();

    const enc = await alice.encrypt(new Uint8Array(0));
    const dec = await bob.decrypt(enc.header, enc.ciphertext, enc.nonce);
    expect(dec.length).toBe(0);
  });

  it("rejects tampered ciphertext", async () => {
    const { alice, bob } = await setupRatchets();

    const msg = new TextEncoder().encode("Secret");
    const enc = await alice.encrypt(msg);

    // Tamper with ciphertext
    const tampered = new Uint8Array(enc.ciphertext);
    tampered[0] = (tampered[0]! + 1) % 256;

    await expect(
      bob.decrypt(enc.header, tampered, enc.nonce),
    ).rejects.toThrow();
  });

  it("increments message numbers correctly", async () => {
    const { alice, bob } = await setupRatchets();

    const enc1 = await alice.encrypt(new TextEncoder().encode("m1"));
    expect(enc1.header.messageNumber).toBe(0);

    const enc2 = await alice.encrypt(new TextEncoder().encode("m2"));
    expect(enc2.header.messageNumber).toBe(1);

    const enc3 = await alice.encrypt(new TextEncoder().encode("m3"));
    expect(enc3.header.messageNumber).toBe(2);
  });

  it("handles many messages in one direction then a reply", async () => {
    const { alice, bob } = await setupRatchets();

    // Alice sends 10 messages
    const encryptedMessages = [];
    for (let i = 0; i < 10; i++) {
      encryptedMessages.push(await alice.encrypt(new TextEncoder().encode(`msg-${i}`)));
    }

    // Bob receives all 10
    for (let i = 0; i < 10; i++) {
      const enc = encryptedMessages[i]!;
      const dec = await bob.decrypt(enc.header, enc.ciphertext, enc.nonce);
      expect(new TextDecoder().decode(dec)).toBe(`msg-${i}`);
    }

    // Bob replies
    const reply = await bob.encrypt(new TextEncoder().encode("got all 10"));
    const decReply = await alice.decrypt(reply.header, reply.ciphertext, reply.nonce);
    expect(new TextDecoder().decode(decReply)).toBe("got all 10");
  });
});
