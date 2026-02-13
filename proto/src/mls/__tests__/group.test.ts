import { describe, it, expect, beforeAll, afterEach } from "vitest";
import fs from "fs";
import path from "path";
import { MlsClient } from "../client.js";
import { ensureSodium, generateIdentityKeyPair } from "../../crypto/index.js";

// Each test uses a fresh MlsClient with its own WASM instance would be ideal,
// but WASM module is shared. We create separate MlsClient instances per "user"
// to simulate multi-party scenarios.

let wasmBytes: Buffer;

beforeAll(async () => {
  await ensureSodium();
  const wasmPath = path.resolve(
    __dirname,
    "../../../mls-wasm/pkg/mls_wasm_bg.wasm",
  );
  wasmBytes = fs.readFileSync(wasmPath);
});

function makeGroupId(): Uint8Array {
  const id = new Uint8Array(16);
  crypto.getRandomValues(id);
  return id;
}

async function setupClient(): Promise<MlsClient> {
  const client = new MlsClient();
  client.init(wasmBytes);
  const identity = await generateIdentityKeyPair();
  const credential = client.createCredential(identity.publicKey);
  client.createSession(credential);
  return client;
}

describe("MLS group creation", () => {
  it("creates a group with one member", async () => {
    const alice = await setupClient();
    const groupId = makeGroupId();

    alice.createGroup(groupId);

    const epoch = alice.getEpoch(groupId);
    expect(epoch).toBe(0);

    const members = alice.getMembers(groupId);
    expect(members).toHaveLength(1);
  });

  it("throws when creating group without session", () => {
    const client = new MlsClient();
    client.init(wasmBytes);
    expect(() => client.createGroup(makeGroupId())).toThrow("No active MLS session");
  });
});

describe("MLS add member", () => {
  it("adds a second member via KeyPackage + Welcome", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    // Alice creates group
    alice.createGroup(groupId);

    // Bob generates a KeyPackage within his session
    const bobPackages = bob.generateSessionKeyPackages(1);
    expect(bobPackages).toHaveLength(1);

    // Alice adds Bob using his KeyPackage
    const { commit, welcome } = alice.addMember(
      groupId,
      bobPackages[0].keyPackageData,
    );
    expect(commit).toBeInstanceOf(Uint8Array);
    expect(commit.length).toBeGreaterThan(0);
    expect(welcome).toBeInstanceOf(Uint8Array);
    expect(welcome.length).toBeGreaterThan(0);

    // Bob processes the Welcome to join the group
    const joinedGroupId = bob.processWelcome(welcome);
    expect(joinedGroupId).toEqual(groupId);

    // Both see 2 members
    const aliceMembers = alice.getMembers(groupId);
    const bobMembers = bob.getMembers(groupId);
    expect(aliceMembers).toHaveLength(2);
    expect(bobMembers).toHaveLength(2);
  });

  it("epoch advances after add", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    alice.createGroup(groupId);
    expect(alice.getEpoch(groupId)).toBe(0);

    const bobPackages = bob.generateSessionKeyPackages(1);
    alice.addMember(groupId, bobPackages[0].keyPackageData);

    // Epoch advances after add+merge
    expect(alice.getEpoch(groupId)).toBe(1);
  });
});

describe("MLS encrypt/decrypt", () => {
  it("two members can exchange encrypted messages", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    // Setup group with both members
    alice.createGroup(groupId);
    const bobPackages = bob.generateSessionKeyPackages(1);
    const { welcome } = alice.addMember(groupId, bobPackages[0].keyPackageData);
    bob.processWelcome(welcome);

    // Alice encrypts a message
    const plaintext = new TextEncoder().encode("Hello from Alice!");
    const ciphertext = alice.encryptMessage(groupId, plaintext);
    expect(ciphertext).toBeInstanceOf(Uint8Array);
    expect(ciphertext.length).toBeGreaterThan(plaintext.length);

    // Bob decrypts it
    const processed = bob.processMessage(groupId, ciphertext);
    expect(processed.messageType).toBe("application");
    expect(new TextDecoder().decode(processed.plaintext)).toBe("Hello from Alice!");

    // Bob encrypts a reply
    const reply = new TextEncoder().encode("Hello from Bob!");
    const replyCiphertext = bob.encryptMessage(groupId, reply);

    // Alice decrypts it
    const processedReply = alice.processMessage(groupId, replyCiphertext);
    expect(processedReply.messageType).toBe("application");
    expect(new TextDecoder().decode(processedReply.plaintext)).toBe("Hello from Bob!");
  });

  it("ciphertext is different for same plaintext", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    alice.createGroup(groupId);
    const bobPkgs = bob.generateSessionKeyPackages(1);
    const { welcome } = alice.addMember(groupId, bobPkgs[0].keyPackageData);
    bob.processWelcome(welcome);

    const plaintext = new TextEncoder().encode("same message");
    const ct1 = alice.encryptMessage(groupId, plaintext);
    const ct2 = alice.encryptMessage(groupId, plaintext);

    // Ciphertexts should differ (ratchet advances)
    expect(ct1).not.toEqual(ct2);

    // Both should decrypt correctly
    const p1 = bob.processMessage(groupId, ct1);
    const p2 = bob.processMessage(groupId, ct2);
    expect(new TextDecoder().decode(p1.plaintext)).toBe("same message");
    expect(new TextDecoder().decode(p2.plaintext)).toBe("same message");
  });
});

describe("MLS three-member group", () => {
  it("three members can all communicate", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const carol = await setupClient();
    const groupId = makeGroupId();

    // Alice creates group, adds Bob
    alice.createGroup(groupId);
    const bobPkgs = bob.generateSessionKeyPackages(1);
    const { welcome: bobWelcome, commit: addBobCommit } = alice.addMember(
      groupId,
      bobPkgs[0].keyPackageData,
    );
    bob.processWelcome(bobWelcome);

    // Alice adds Carol
    const carolPkgs = carol.generateSessionKeyPackages(1);
    const { welcome: carolWelcome, commit: addCarolCommit } = alice.addMember(
      groupId,
      carolPkgs[0].keyPackageData,
    );

    // Bob processes the add-Carol commit
    bob.processMessage(groupId, addCarolCommit);
    // Carol processes her Welcome
    carol.processWelcome(carolWelcome);

    // All three see 3 members
    expect(alice.getMembers(groupId)).toHaveLength(3);
    expect(bob.getMembers(groupId)).toHaveLength(3);
    expect(carol.getMembers(groupId)).toHaveLength(3);

    // Alice sends, both Bob and Carol can decrypt
    const msg = new TextEncoder().encode("Hello group!");
    const ct = alice.encryptMessage(groupId, msg);

    const bobResult = bob.processMessage(groupId, ct);
    expect(new TextDecoder().decode(bobResult.plaintext)).toBe("Hello group!");

    // Carol gets a fresh copy of the ciphertext (each member decrypts independently)
    // Actually in MLS, the same ciphertext is sent to everyone
    // but each member uses their own ratchet state, so we need
    // separate ciphertexts for each recipient
    // Actually no - MLS uses a shared group key, so the same ciphertext
    // works for all members. But the tree-based ratchet means
    // the sender's state advances after encryption, and each recipient
    // can decrypt the same ciphertext independently.
    // However, we already consumed the ciphertext for Bob above,
    // which advanced Bob's ratchet. Carol should also be able to decrypt.
    // But wait - in this WASM implementation, process_message mutates
    // the group state. So each call to process_message on the same ciphertext
    // would need a separate client. Since Bob already processed it,
    // Carol would need her own copy.
    // Actually Carol IS a separate client with separate state!
    const carolResult = carol.processMessage(groupId, ct);
    expect(new TextDecoder().decode(carolResult.plaintext)).toBe("Hello group!");

    // Bob sends, Alice and Carol decrypt
    const bobMsg = new TextEncoder().encode("Bob here!");
    const bobCt = bob.encryptMessage(groupId, bobMsg);

    const aliceResult = alice.processMessage(groupId, bobCt);
    expect(new TextDecoder().decode(aliceResult.plaintext)).toBe("Bob here!");

    const carolResult2 = carol.processMessage(groupId, bobCt);
    expect(new TextDecoder().decode(carolResult2.plaintext)).toBe("Bob here!");
  });
});

describe("MLS remove member", () => {
  it("removed member cannot decrypt new messages (forward secrecy)", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const carol = await setupClient();
    const groupId = makeGroupId();

    // Build 3-member group
    alice.createGroup(groupId);
    const bobPkgs = bob.generateSessionKeyPackages(1);
    const { welcome: bobWelcome } = alice.addMember(
      groupId,
      bobPkgs[0].keyPackageData,
    );
    bob.processWelcome(bobWelcome);

    const carolPkgs = carol.generateSessionKeyPackages(1);
    const { welcome: carolWelcome, commit: addCarolCommit } = alice.addMember(
      groupId,
      carolPkgs[0].keyPackageData,
    );
    bob.processMessage(groupId, addCarolCommit);
    carol.processWelcome(carolWelcome);

    // Find Carol's leaf index
    const members = alice.getMembers(groupId);
    const carolMember = members.find(
      (m) => m.index !== alice.getMembers(groupId)[0].index &&
             m.index !== members.find((x) => x.index !== members[0].index)?.index,
    );
    // Carol should be at index 2 (alice=0, bob=1, carol=2)
    // But leaf indices in MLS may not be sequential. Let's find the right one.
    expect(members).toHaveLength(3);

    // Alice removes Carol (last member added)
    // In the binary tree, leaf indices are 0, 1, 2 for Alice, Bob, Carol
    const carolLeafIndex = members[2].index;
    const removeCommit = alice.removeMember(groupId, carolLeafIndex);

    // Bob processes the remove commit
    bob.processMessage(groupId, removeCommit);

    // Alice and Bob should now see 2 members
    expect(alice.getMembers(groupId)).toHaveLength(2);
    expect(bob.getMembers(groupId)).toHaveLength(2);

    // Alice sends a message after removal
    const msg = new TextEncoder().encode("Secret after removal");
    const ct = alice.encryptMessage(groupId, msg);

    // Bob can decrypt
    const bobResult = bob.processMessage(groupId, ct);
    expect(new TextDecoder().decode(bobResult.plaintext)).toBe("Secret after removal");

    // Carol cannot decrypt (she was removed)
    expect(() => carol.processMessage(groupId, ct)).toThrow();
  });

  it("epoch advances after remove", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    alice.createGroup(groupId);
    const bobPkgs = bob.generateSessionKeyPackages(1);
    const { welcome } = alice.addMember(groupId, bobPkgs[0].keyPackageData);
    bob.processWelcome(welcome);

    const epochBeforeRemove = alice.getEpoch(groupId);
    const members = alice.getMembers(groupId);
    const bobLeafIndex = members[1].index;

    alice.removeMember(groupId, bobLeafIndex);

    expect(alice.getEpoch(groupId)).toBe(epochBeforeRemove + 1);
  });
});

describe("MLS epoch tracking", () => {
  it("epoch advances on each add/remove", async () => {
    const alice = await setupClient();
    const bob = await setupClient();
    const groupId = makeGroupId();

    alice.createGroup(groupId);
    expect(alice.getEpoch(groupId)).toBe(0);

    const bobPkgs = bob.generateSessionKeyPackages(1);
    alice.addMember(groupId, bobPkgs[0].keyPackageData);
    expect(alice.getEpoch(groupId)).toBe(1);

    const members = alice.getMembers(groupId);
    alice.removeMember(groupId, members[1].index);
    expect(alice.getEpoch(groupId)).toBe(2);
  });
});

describe("MLS session lifecycle", () => {
  it("destroySession cleans up", async () => {
    const client = await setupClient();
    const groupId = makeGroupId();
    client.createGroup(groupId);

    client.destroySession();

    // Operations should fail after session is destroyed
    expect(() => client.getEpoch(groupId)).toThrow();
  });

  it("createSession replaces existing session", async () => {
    const client = new MlsClient();
    client.init(wasmBytes);

    const id1 = await generateIdentityKeyPair();
    const cred1 = client.createCredential(id1.publicKey);
    client.createSession(cred1);

    const groupId = makeGroupId();
    client.createGroup(groupId);

    // Create new session (replaces old)
    const id2 = await generateIdentityKeyPair();
    const cred2 = client.createCredential(id2.publicKey);
    client.createSession(cred2);

    // Old group should not be found in new session
    expect(() => client.getEpoch(groupId)).toThrow("group not found");
  });
});
