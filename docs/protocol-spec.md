# Cairn Protocol Specification

**Protocol Name:** `cairn`
**Version:** `0.1.0`
**Status:** Draft
**Date:** 2026-02-09
**Authors:** Cairn Contributors

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Terminology](#2-terminology)
3. [ActivityPub Extensions](#3-activitypub-extensions)
4. [Federation Handshake](#4-federation-handshake)
5. [Message Envelope](#5-message-envelope)
6. [End-to-End Encryption](#6-end-to-end-encryption)
7. [Privacy Manifest](#7-privacy-manifest)
8. [Protocol Versioning](#8-protocol-versioning)
9. [Message Formatting](#9-message-formatting)
10. [Appendices](#10-appendices)

---

## 1. Introduction

### 1.1 Purpose

This document specifies the Cairn protocol, a federated communication protocol designed for privacy-first, decentralized group communication. Cairn provides functionality comparable to centralized platforms such as Discord -- text channels, voice chat, roles, moderation -- while guaranteeing that no single entity controls the network and that private communications are end-to-end encrypted by default.

This specification is the normative reference for all Cairn server and client implementations. Implementors MUST conform to this document to achieve interoperability within the Cairn federation.

### 1.2 Design Principles

The following principles govern every protocol decision. When ambiguity arises, these principles take precedence in the order listed.

1. **The server is untrusted by design.** Even a malicious node operator MUST only be able to observe public channel content and encrypted blobs for everything else. The server acts as a relay and storage service; it MUST NOT require access to plaintext private content to function.

2. **No centralization.** Every node is independently hosted and operated. There is no central directory, no mandatory bootstrap node, no single point of failure. Nodes MAY choose to use shared infrastructure (e.g., cloud providers) but the protocol MUST NOT depend on any specific provider or service.

3. **Privacy is a protocol requirement, not a feature.** End-to-end encryption for DMs and private channels is mandatory and MUST NOT be possible to disable at the node operator level. Metadata minimization is enforced at federation boundaries.

4. **Federation with sovereignty.** Each node controls its own moderation policies, data retention, and federation relationships. Nodes can defederate from any other node at any time for any reason.

5. **Metadata minimization.** The protocol collects and transmits only the minimum metadata necessary for message delivery, ordering, and authentication. Fields that are not strictly required for protocol operation are explicitly excluded from the message envelope.

### 1.3 Conformance

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

A conforming Cairn server MUST implement all normative requirements in Sections 3 through 8. A conforming Cairn client MUST implement all requirements in Sections 5, 6, and 9.

### 1.4 Notation

JSON examples in this document use relaxed formatting for readability. Actual implementations MUST produce valid JSON (or JSON-LD where specified). Ellipses (`...`) in examples indicate omitted fields.

---

## 2. Terminology

| Term | Definition |
|------|-----------|
| **Node** | A single Cairn server instance, identified by its domain name and Ed25519 public key. A node hosts users, channels, and messages. Synonymous with "instance" in other federated systems. |
| **Server** (Cairn Server) | A logical community hosted on a node, analogous to a Discord "server" or "guild." A single node MAY host multiple Cairn Servers. Each server has its own channels, roles, and membership. |
| **Channel** | A named communication stream within a server. Channels have a type (`public`, `private`, or `dm`) and an optional encryption status. |
| **Actor** | An entity with an ActivityPub identity, identified by a URI. In Cairn, actors are users, servers, and bots. Each actor has an inbox for receiving activities and an outbox for publishing them. |
| **HLC (Hybrid Logical Clock)** | A timestamp mechanism that combines physical wall-clock time with a logical counter and node identifier. HLCs provide causal ordering of events across distributed nodes without requiring synchronized clocks. See [Appendix A](#appendix-a-hybrid-logical-clock-algorithm). |
| **MLS (Messaging Layer Security)** | A protocol for group key agreement defined in [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420). Cairn uses MLS for end-to-end encrypted group channels. MLS provides forward secrecy and post-compromise security with efficient O(log n) group operations. |
| **X3DH (Extended Triple Diffie-Hellman)** | A key agreement protocol used to establish a shared secret between two parties who may not be online simultaneously. Used in Cairn for DM session initiation. |
| **Double Ratchet** | A key management algorithm that provides forward secrecy and break-in recovery for ongoing message sessions. Used for DM encryption after the X3DH handshake. |
| **DID (Decentralized Identifier)** | A self-certifying identifier in the form `did:cairn:<base58(SHA-256(genesis_op))>`. Derived from a user's genesis operation and stable across key rotations. Enables portable identity across instances. |
| **Operation Chain** | A hash-linked, signed sequence of DID operations (create, rotate_signing_key, rotate_rotation_key, update_handle, deactivate). Each operation references the SHA-256 hash of the previous operation. Signed by the rotation key. Tamper-evident and independently verifiable. |
| **Signing Key** | An Ed25519 key pair used for daily operations: E2EE, message signing, MLS credentials. This is the existing identity key. Can be rotated without changing the DID. |
| **Rotation Key** | An Ed25519 key pair used exclusively for DID operations (key rotation, handle changes, deactivation). Generated at registration. Stored in encrypted key backup. Recovery codes can rotate this key as a last resort. |
| **Federated Auth Token** | A time-limited, node-signed token that allows a user to authenticate with a remote instance without creating a local account. Format: `base64url(payload).base64url(node_ed25519_signature)`. |
| **Federation** | The process by which two or more independent nodes exchange messages and synchronize state. Federation is always opt-in per node. |
| **Defederation** | The process by which a node severs its federation relationship with another node, ceasing all message exchange. |
| **KeyPackage** | An MLS-specific structure containing a user's public key material, used by other group members to add that user to an MLS group. KeyPackages are single-use. |
| **Epoch** | An MLS concept representing a version of the group state. Each membership change (add, remove, update) advances the epoch. Messages are encrypted under a specific epoch's keys. |
| **Privacy Manifest** | A JSON document published by each node describing its data handling practices: what is logged, retention durations, and federation metadata policies. |
| **Tombstone** | A marker left in place of a deleted message. Tombstones preserve causal ordering and synchronization state while removing content. |
| **Activity** | An ActivityPub object representing an action (Create, Update, Delete, Follow, Accept, Reject, etc.). Activities are the fundamental unit of federation. |

---

## 3. ActivityPub Extensions

Cairn extends the [ActivityPub](https://www.w3.org/TR/activitypub/) protocol and [Activity Streams 2.0](https://www.w3.org/TR/activitystreams-core/) vocabulary with custom types specific to real-time group communication. All Cairn-specific types and properties are defined under the namespace `https://cairn.chat/ns#`.

### 3.1 JSON-LD Context

All Cairn ActivityPub documents MUST include both the standard Activity Streams context and the Cairn namespace in their `@context` field:

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    {
      "cairn": "https://cairn.chat/ns#",
      "CairnServer": "cairn:CairnServer",
      "CairnChannel": "cairn:CairnChannel",
      "CairnMessage": "cairn:CairnMessage",
      "CairnRole": "cairn:CairnRole",
      "CairnReaction": "cairn:CairnReaction",
      "hlcTimestamp": "cairn:hlcTimestamp",
      "channelType": "cairn:channelType",
      "encryptedContent": "cairn:encryptedContent",
      "nonce": "cairn:nonce",
      "mlsEpoch": "cairn:mlsEpoch",
      "permissions": "cairn:permissions",
      "rolePriority": "cairn:rolePriority",
      "protocolVersion": "cairn:protocolVersion",
      "privacyManifest": "cairn:privacyManifest",
      "emoji": "cairn:emoji",
      "signature": "cairn:signature",
      "did": "cairn:did",
      "homeInstance": "cairn:homeInstance",
      "displayName": "cairn:displayName",
      "channelId": "cairn:channelId"
    }
  ]
}
```

Implementations MAY use the compact form by referencing a published context document:

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ]
}
```

### 3.2 CairnServer

Represents a logical community (guild/server) hosted on a node. Extends the ActivityStreams `Group` type.

**Properties:**

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | String | MUST | `"CairnServer"` |
| `id` | URI | MUST | Globally unique URI for this server |
| `name` | String | MUST | Display name of the server |
| `summary` | String | SHOULD | Description of the server |
| `icon` | Image | MAY | Server icon |
| `published` | DateTime | MUST | ISO 8601 creation timestamp |
| `attributedTo` | URI | MUST | URI of the hosting node's actor |
| `followers` | URI | MUST | Collection URI for members |
| `protocolVersion` | String | MUST | Cairn protocol version (e.g., `"0.1.0"`) |

**Example:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnServer",
  "id": "https://node-a.example.com/servers/550e8400-e29b-41d4-a716-446655440000",
  "name": "Elixir Developers",
  "summary": "A community for Elixir and Erlang developers",
  "icon": {
    "type": "Image",
    "url": "https://node-a.example.com/media/server-icon.png",
    "mediaType": "image/png"
  },
  "published": "2026-02-01T00:00:00Z",
  "attributedTo": "https://node-a.example.com/actor",
  "followers": "https://node-a.example.com/servers/550e8400-e29b-41d4-a716-446655440000/members",
  "protocolVersion": "0.1.0"
}
```

### 3.3 CairnChannel

Represents a communication channel within a server. A channel may be public (plaintext, visible to all members), private (end-to-end encrypted via MLS, invite-only), or a DM (end-to-end encrypted via X3DH/Double Ratchet, exactly two members).

**Properties:**

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | String | MUST | `"CairnChannel"` |
| `id` | URI | MUST | Globally unique URI for this channel |
| `name` | String | MUST | Channel display name (e.g., `"general"`) |
| `summary` | String | MAY | Channel topic/description |
| `channelType` | String | MUST | One of: `"public"`, `"private"`, `"dm"` |
| `context` | URI | MUST | URI of the parent `CairnServer` |
| `published` | DateTime | MUST | ISO 8601 creation timestamp |
| `attributedTo` | URI | MUST | URI of the channel creator |
| `followers` | URI | MUST | Collection URI for channel members/subscribers |
| `encryptedContent` | Boolean | MUST | `true` if channel uses E2E encryption |

**Example:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnChannel",
  "id": "https://node-a.example.com/channels/7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "name": "general",
  "summary": "General discussion for the community",
  "channelType": "public",
  "context": "https://node-a.example.com/servers/550e8400-e29b-41d4-a716-446655440000",
  "published": "2026-02-01T00:00:01Z",
  "attributedTo": "https://node-a.example.com/users/alice",
  "followers": "https://node-a.example.com/channels/7c9e6679-7425-40de-944b-e07fc1f90ae7/subscribers",
  "encryptedContent": false
}
```

### 3.4 CairnMessage

Represents a message within a channel. Extends the ActivityStreams `Note` type. For public channels, the `content` field holds plaintext. For encrypted channels, `content` MUST be `null` and `encryptedContent` MUST hold the ciphertext.

**Properties:**

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | String | MUST | `"CairnMessage"` |
| `id` | URI | MUST | Globally unique URI for this message |
| `attributedTo` | URI | MUST | URI of the message author |
| `context` | URI | MUST | URI of the parent `CairnChannel` |
| `content` | String or null | MUST | Plaintext content (public channels) or `null` (encrypted channels) |
| `encryptedContent` | String or null | Conditional | Base64url-encoded ciphertext. MUST be present when the channel is encrypted. MUST be `null` or absent for public channels. |
| `nonce` | String or null | Conditional | Base64url-encoded encryption nonce. MUST accompany `encryptedContent`. |
| `mlsEpoch` | Integer or null | Conditional | MLS epoch number. MUST be present for MLS-encrypted messages. |
| `inReplyTo` | URI or null | MAY | URI of the parent message (for threads) |
| `published` | DateTime | MUST | ISO 8601 timestamp |
| `hlcTimestamp` | Object | MUST | Hybrid Logical Clock timestamp (see Section 5) |
| `signature` | String | MUST | Base64url-encoded Ed25519 signature over the canonical message fields |
| `protocolVersion` | String | MUST | Protocol version (e.g., `"0.1.0"`) |
| `cairn:channelId` | String | SHOULD | Channel UUID for routing on the receiving node |
| `cairn:did` | String | SHOULD | Author's `did:cairn:...` identifier for cross-instance identity verification |
| `cairn:homeInstance` | String | SHOULD | Author's home instance domain |
| `cairn:displayName` | String | MAY | Author's display name at time of sending |

**Example (public channel message):**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnMessage",
  "id": "https://node-a.example.com/messages/a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "attributedTo": "https://node-a.example.com/users/alice",
  "context": "https://node-a.example.com/channels/7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "content": "Hello everyone! Welcome to the Elixir Developers community.",
  "encryptedContent": null,
  "nonce": null,
  "mlsEpoch": null,
  "inReplyTo": null,
  "published": "2026-02-09T14:30:00Z",
  "hlcTimestamp": {
    "wall": 1739108400000,
    "counter": 0,
    "node": "node-a.example.com"
  },
  "signature": "bWVzc2FnZSBzaWduYXR1cmUgZXhhbXBsZQ...",
  "protocolVersion": "0.1.0"
}
```

**Example (encrypted channel message):**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnMessage",
  "id": "https://node-a.example.com/messages/b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "attributedTo": "https://node-a.example.com/users/alice",
  "context": "https://node-a.example.com/channels/encrypted-channel-uuid",
  "content": null,
  "encryptedContent": "xTkBjL2mVcOh4R3nNqK8vbZ1wPdA5eFgHi...",
  "nonce": "Q7rM2sNpK1vXwYzA3bCdEfGh",
  "mlsEpoch": 42,
  "inReplyTo": null,
  "published": "2026-02-09T14:31:00Z",
  "hlcTimestamp": {
    "wall": 1739108460000,
    "counter": 0,
    "node": "node-a.example.com"
  },
  "signature": "ZW5jcnlwdGVkIG1lc3NhZ2Ugc2lnbmF0dXJl...",
  "protocolVersion": "0.1.0"
}
```

### 3.5 CairnRole

Represents a permission role within a server. Roles are ordered by priority and their permissions are additive (higher-priority roles override lower-priority ones).

**Properties:**

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | String | MUST | `"CairnRole"` |
| `id` | URI | MUST | Globally unique URI for this role |
| `name` | String | MUST | Display name (e.g., `"Moderator"`) |
| `context` | URI | MUST | URI of the parent `CairnServer` |
| `rolePriority` | Integer | MUST | Priority for permission resolution (higher number = higher priority) |
| `permissions` | Object | MUST | Map of permission keys to boolean values |

**Defined permissions:**

| Permission Key | Description |
|---------------|-------------|
| `send_messages` | Send messages in channels |
| `read_messages` | Read messages in channels |
| `manage_messages` | Delete or pin messages authored by others |
| `manage_channels` | Create, edit, delete channels |
| `manage_roles` | Create, edit, delete roles |
| `manage_server` | Edit server settings |
| `kick_members` | Kick members from the server |
| `ban_members` | Ban members from the server |
| `invite_members` | Create invite links |
| `manage_webhooks` | Create and manage webhooks |
| `attach_files` | Upload files to channels |
| `use_voice` | Join voice channels |
| `mute_members` | Server-mute other members in voice |
| `deafen_members` | Server-deafen other members in voice |
| `move_members` | Move members between voice channels |

**Example:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnRole",
  "id": "https://node-a.example.com/servers/550e8400-e29b-41d4-a716-446655440000/roles/moderator",
  "name": "Moderator",
  "context": "https://node-a.example.com/servers/550e8400-e29b-41d4-a716-446655440000",
  "rolePriority": 50,
  "permissions": {
    "send_messages": true,
    "read_messages": true,
    "manage_messages": true,
    "manage_channels": true,
    "manage_roles": false,
    "manage_server": false,
    "kick_members": true,
    "ban_members": true,
    "invite_members": true,
    "manage_webhooks": true,
    "attach_files": true,
    "use_voice": true,
    "mute_members": true,
    "deafen_members": true,
    "move_members": true
  }
}
```

### 3.6 CairnReaction

Represents an emoji reaction on a message. Extends the ActivityStreams `Like` type with an `emoji` property.

**Properties:**

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | String | MUST | `"CairnReaction"` |
| `id` | URI | MUST | Globally unique URI for this reaction |
| `actor` | URI | MUST | URI of the user who reacted |
| `object` | URI | MUST | URI of the message being reacted to |
| `emoji` | String | MUST | Unicode emoji character or shortcode (e.g., `"\ud83d\udc4d"` or `":thumbsup:"`) |
| `published` | DateTime | MUST | ISO 8601 timestamp |

**Example:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "CairnReaction",
  "id": "https://node-a.example.com/reactions/c3d4e5f6-a7b8-9012-cdef-123456789012",
  "actor": "https://node-a.example.com/users/bob",
  "object": "https://node-a.example.com/messages/a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "emoji": "\ud83d\udc4d",
  "published": "2026-02-09T14:32:00Z"
}
```

### 3.7 Activity Wrapping

All Cairn objects are transmitted between nodes wrapped in standard ActivityPub activities. The wrapping follows the ActivityPub specification:

| Action | Activity Type | Object |
|--------|--------------|--------|
| New message | `Create` | `CairnMessage` |
| Edit message | `Update` | `CairnMessage` (with updated content) |
| Delete message | `Delete` | `Tombstone` with `formerType: "CairnMessage"` |
| Add reaction | `Create` | `CairnReaction` |
| Remove reaction | `Delete` | `Tombstone` with `formerType: "CairnReaction"` |
| Join channel | `Follow` | `CairnChannel` |
| Approve join | `Accept` | Original `Follow` activity |
| Reject join | `Reject` | Original `Follow` activity |
| Leave channel | `Undo` | Original `Follow` activity |
| DM hint (cross-instance) | `Invite` | `cairn:DmHint` |

**Example (Create activity wrapping a message):**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "Create",
  "id": "https://node-a.example.com/activities/d4e5f6a7-b8c9-0123-def4-567890123456",
  "actor": "https://node-a.example.com/users/alice",
  "published": "2026-02-09T14:30:00Z",
  "to": [
    "https://node-b.example.com/channels/7c9e6679-7425-40de-944b-e07fc1f90ae7/subscribers"
  ],
  "object": {
    "type": "CairnMessage",
    "id": "https://node-a.example.com/messages/a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "attributedTo": "https://node-a.example.com/users/alice",
    "context": "https://node-a.example.com/channels/7c9e6679-7425-40de-944b-e07fc1f90ae7",
    "content": "Hello from node A!",
    "hlcTimestamp": {
      "wall": 1739108400000,
      "counter": 0,
      "node": "node-a.example.com"
    },
    "published": "2026-02-09T14:30:00Z",
    "signature": "bWVzc2FnZSBzaWduYXR1cmUgZXhhbXBsZQ...",
    "protocolVersion": "0.1.0"
  }
}
```

#### DM Hint Activity (Cross-Instance DM)

When a user initiates a cross-instance DM, their home instance delivers a lightweight `Invite` activity to the recipient's home instance. This hint contains only metadata (no message content) and serves as a DM request notification.

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "Invite",
  "actor": "https://instance-a.example.com/users/alice",
  "object": {
    "type": "cairn:DmHint",
    "cairn:channelId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "cairn:senderDid": "did:cairn:alice123...",
    "cairn:senderUsername": "alice",
    "cairn:senderDisplayName": "Alice",
    "cairn:recipientDid": "did:cairn:bob456..."
  },
  "target": "https://instance-b.example.com/users/bob"
}
```

| Property | Type | Requirement | Description |
|----------|------|-------------|-------------|
| `type` | string | MUST | `"cairn:DmHint"` |
| `cairn:channelId` | UUID | MUST | Channel ID on the initiator's instance |
| `cairn:senderDid` | string | MUST | Sender's `did:cairn:...` identifier |
| `cairn:senderUsername` | string | MUST | Sender's username |
| `cairn:senderDisplayName` | string | MAY | Sender's display name |
| `cairn:recipientDid` | string | MUST | Recipient's `did:cairn:...` identifier |

The receiving instance MUST:
1. Resolve the `recipientDid` to a local user
2. Create a DM request notification for the recipient
3. Return `:ok` on success, or an appropriate error if the recipient is not found

DM **messages** are NEVER delivered via federation. Only the hint (request) crosses instances. The recipient, upon accepting, connects to the initiator's instance via federated auth token + WebSocket.

---

## 4. Federation Handshake

Federation is the process by which two Cairn nodes establish a trust relationship and begin exchanging activities. All federation is opt-in: a node MUST explicitly initiate or accept federation with another node.

### 4.1 Node Identity

Each Cairn node MUST generate the following cryptographic material on first boot:

1. **Ed25519 signing key pair** -- Used to sign all outbound federated activities and to authenticate the node's identity. The private key MUST be stored securely and MUST NOT be transmitted over the network.

2. **TLS certificate** -- Used for HTTPS and mutual TLS (mTLS). Nodes SHOULD use certificates issued by a publicly trusted Certificate Authority (e.g., Let's Encrypt). Self-signed certificates MAY be used but require manual trust establishment.

The node's **identity** is the combination of its domain name and its Ed25519 public key. Changing either of these values constitutes a new node identity from the perspective of federated peers.

### 4.1.1 User Identity (`did:cairn`)

Each user has a portable cryptographic identity represented as a Decentralized Identifier (DID). The DID is self-certifying — its value is derived from cryptographic material, not assigned by any authority.

**Two key pairs per user:**

- **Signing key** (Ed25519) — used for E2EE, message signing, MLS credentials, and daily operations. This is the user's existing `identity_public_key`.
- **Rotation key** (Ed25519) — used ONLY for DID operations (key rotation, handle changes, deactivation). Generated at registration. Stored in the encrypted key backup.

**DID derivation:**

1. Create the genesis operation:
   ```json
   {
     "type": "create",
     "signingKey": "<multibase Ed25519 public key>",
     "rotationKey": "<multibase Ed25519 public key>",
     "handle": "<username>",
     "service": "<home_domain>",
     "prev": null
   }
   ```
2. Sign the genesis operation with the rotation key.
3. Compute `DID = did:cairn:<base58(SHA-256(canonical_json(signed_genesis_op)))>`.
4. The DID never changes, regardless of key rotations.

**Operation chain:**

DID state is managed through a hash-linked sequence of signed operations:

```
Op 0 (genesis): {type: "create", signingKey, rotationKey, handle, service, prev: null}
Op 1:           {type: "rotate_signing_key", key: "<new>", prev: SHA-256(Op 0)}
Op 2:           {type: "update_handle", handle: "<new>", prev: SHA-256(Op 1)}
Op 3:           {type: "rotate_rotation_key", key: "<new>", prev: SHA-256(Op 2)}
```

Each operation is signed by the **current rotation key** at the time of signing. The chain is tamper-evident: modifying any operation invalidates all subsequent hashes.

**DID document** (constructed by replaying the operation chain):

```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:cairn:7xK9...",
  "verificationMethod": [{
    "id": "did:cairn:7xK9...#signing",
    "type": "Ed25519VerificationKey2020",
    "publicKeyMultibase": "z6Mk..."
  }],
  "authentication": ["did:cairn:7xK9...#signing"],
  "service": [{
    "type": "CairnPDS",
    "serviceEndpoint": "https://home.instance.com"
  }]
}
```

**DID resolution endpoint:**

```
GET /.well-known/did/<did>
```

Returns the DID document. The receiving node can independently verify the document by replaying the operation chain.

**Federated authentication token:**

When a user wants to join a server on a remote instance, their home instance issues a federated auth token:

```json
{
  "type": "federated_auth",
  "did": "did:cairn:7xK9...",
  "username": "alice",
  "display_name": "Alice",
  "home_instance": "instance-a.com",
  "target_instance": "instance-b.com",
  "public_key": "<base64 Ed25519 pubkey>",
  "iat": 1739280000,
  "exp": 1739283600,
  "nonce": "<random 16 bytes hex>"
}
```

Wire format: `base64url(payload).base64url(node_ed25519_signature)`. Signed by the **home node's** Ed25519 key. The remote instance verifies the signature against the home node's public key from `federated_nodes`, then verifies the user's DID operation chain.

**DM guard:** Messages from DM channels (`type: "dm"`) or channels without a `server_id` MUST NOT be federated. DMs always stay on the home instance.

### 4.2 Well-Known Federation Endpoint

Every Cairn node MUST serve a JSON document at the well-known federation URL:

```
GET /.well-known/cairn-federation
```

The response MUST have `Content-Type: application/json` and MUST contain the following fields:

```json
{
  "node_id": "550e8400-e29b-41d4-a716-446655440000",
  "domain": "node-a.example.com",
  "public_key": "MCowBQYDK2VwAyEAGb1gauf46Lv4SISaOmlBCPLbmGxLoAMMNjNFBjntbmQ=",
  "public_key_algorithm": "ed25519",
  "protocol_name": "cairn",
  "protocol_version": "0.1.0",
  "supported_versions": ["0.1.0"],
  "software": "cairn",
  "software_version": "0.1.0",
  "inbox": "https://node-a.example.com/inbox",
  "privacy_manifest_url": "https://node-a.example.com/.well-known/privacy-manifest",
  "privacy_manifest": {
    "version": "1.0",
    "logging": {
      "ip_addresses": false,
      "message_content": false,
      "federation_metadata": false
    },
    "retention": {
      "messages_days": 365,
      "files_days": 90,
      "audit_log_days": 730
    },
    "federation": {
      "metadata_stripped": true,
      "read_receipts": false
    }
  }
}
```

**Field definitions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `node_id` | UUID | MUST | Unique identifier for this node, generated once on first boot |
| `domain` | String | MUST | Fully qualified domain name of this node |
| `public_key` | String | MUST | Base64-encoded Ed25519 public key |
| `public_key_algorithm` | String | MUST | MUST be `"ed25519"` |
| `protocol_name` | String | MUST | MUST be `"cairn"` |
| `protocol_version` | String | MUST | Current protocol version (semver) |
| `supported_versions` | Array | MUST | All protocol versions this node supports |
| `software` | String | SHOULD | Software implementation name |
| `software_version` | String | SHOULD | Software version |
| `inbox` | URI | MUST | Server-level ActivityPub inbox URL |
| `privacy_manifest_url` | URI | MUST | URL to the full privacy manifest document |
| `privacy_manifest` | Object | MUST | Inline copy of the privacy manifest (see Section 7) |

Implementations MUST serve this endpoint over HTTPS. The endpoint MUST NOT require authentication. The response SHOULD include appropriate cache headers (e.g., `Cache-Control: max-age=3600`).

### 4.3 WebFinger

Cairn nodes MUST implement the WebFinger protocol ([RFC 7033](https://www.rfc-editor.org/rfc/rfc7033)) for user discovery. Remote nodes use WebFinger to resolve a `username@domain` identifier to an ActivityPub actor URI.

**Request:**

```
GET /.well-known/webfinger?resource=acct:alice@node-a.example.com
```

**Response:**

```json
{
  "subject": "acct:alice@node-a.example.com",
  "aliases": [
    "https://node-a.example.com/users/alice"
  ],
  "links": [
    {
      "rel": "self",
      "type": "application/activity+json",
      "href": "https://node-a.example.com/users/alice"
    },
    {
      "rel": "http://webfinger.net/rel/profile-page",
      "type": "text/html",
      "href": "https://node-a.example.com/@alice"
    }
  ]
}
```

The `self` link with type `application/activity+json` MUST be present and MUST point to the user's ActivityPub actor document. Nodes MUST respond with `404 Not Found` for unknown users. Nodes MUST NOT enumerate users (i.e., the endpoint MUST NOT accept wildcard queries).

WebFinger also supports `did:cairn:...` resources. When the `resource` parameter is a DID, the node MUST resolve it to the corresponding actor URI:

**Request:**

```
GET /.well-known/webfinger?resource=did:cairn:7xK9abc123...
```

**Response:**

```json
{
  "subject": "did:cairn:7xK9abc123...",
  "aliases": [
    "https://node-a.example.com/users/alice"
  ],
  "links": [
    {
      "rel": "self",
      "type": "application/activity+json",
      "href": "https://node-a.example.com/users/alice"
    }
  ]
}
```

### 4.4 Mutual TLS (mTLS)

Node-to-node communication MUST use mutual TLS for transport security and mutual authentication. The handshake proceeds as follows:

1. **Initiating node** connects to the remote node over HTTPS.
2. **Receiving node** presents its TLS server certificate.
3. **Initiating node** verifies the server certificate against its trust store.
4. **Receiving node** requests a client certificate from the initiating node.
5. **Initiating node** presents its TLS client certificate.
6. **Receiving node** verifies the client certificate.

If mTLS is not possible (e.g., the receiving node does not support client certificate requests), nodes MUST fall back to HTTP Message Signatures (Section 4.6 / [Appendix B](#appendix-b-http-message-signatures-rfc-9421)) for authentication. In this case, all federated requests MUST be signed with the node's Ed25519 key and the receiving node MUST verify the signature before processing.

### 4.5 Federation Handshake Flow

The complete federation handshake between two nodes proceeds as follows:

```
Node A (initiator)                          Node B (responder)
      |                                            |
      |  1. GET /.well-known/cairn-federation  |
      |------------------------------------------->|
      |<-------------------------------------------|
      |     (Node B's identity + privacy manifest) |
      |                                            |
      |  2. Verify TLS certificate                 |
      |  3. Verify protocol_name == "cairn"    |
      |  4. Negotiate protocol version             |
      |  5. Validate privacy manifest              |
      |                                            |
      |  6. POST /inbox (Follow activity)          |
      |------------------------------------------->|
      |     (signed with Node A's Ed25519 key)     |
      |                                            |
      |         7. Node B verifies HTTP Signature  |
      |         8. Node B fetches Node A's         |
      |            /.well-known/cairn-federation
      |<-------------------------------------------|
      |         9. Node B validates Node A         |
      |                                            |
      |  10. POST /inbox (Accept activity)         |
      |<-------------------------------------------|
      |     (signed with Node B's Ed25519 key)     |
      |                                            |
      |  [Federation established]                  |
      |                                            |
```

**Step details:**

1. Node A fetches Node B's well-known federation document.
2. Node A verifies that Node B's TLS certificate is valid for the claimed domain.
3. Node A verifies that `protocol_name` is `"cairn"`.
4. Node A computes the intersection of `supported_versions` between both nodes and selects the highest common version. If no common version exists, federation MUST be rejected.
5. Node A evaluates Node B's privacy manifest against local policy. If the manifest does not meet the node operator's minimum requirements, federation MAY be rejected.
6. Node A sends a `Follow` activity to Node B's inbox, requesting federation. This activity is signed with Node A's Ed25519 private key using HTTP Message Signatures ([RFC 9421](https://www.rfc-editor.org/rfc/rfc9421)).
7. Node B verifies the HTTP Signature on the incoming request.
8. Node B fetches Node A's well-known federation document to learn Node A's public key and validate its identity.
9. Node B verifies Node A's TLS certificate, protocol compatibility, and privacy manifest.
10. Node B sends an `Accept` activity to Node A's inbox (or a `Reject` if the federation request is denied).

**Follow activity for federation:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "Follow",
  "id": "https://node-a.example.com/activities/federation-follow-uuid",
  "actor": "https://node-a.example.com/actor",
  "object": "https://node-b.example.com/actor",
  "published": "2026-02-09T12:00:00Z"
}
```

**Accept activity for federation:**

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "type": "Accept",
  "id": "https://node-b.example.com/activities/federation-accept-uuid",
  "actor": "https://node-b.example.com/actor",
  "object": {
    "type": "Follow",
    "id": "https://node-a.example.com/activities/federation-follow-uuid",
    "actor": "https://node-a.example.com/actor",
    "object": "https://node-b.example.com/actor"
  },
  "published": "2026-02-09T12:00:01Z"
}
```

### 4.6 Channel Subscription

Once two nodes are federated, users on one node can subscribe to channels on the other. Channel subscription uses the same Follow/Accept mechanism:

1. The remote user's home node sends a `Follow` activity targeting the channel URI.
2. The hosting node evaluates permissions:
   - **Public channels**: Auto-accept unless the remote node is blocked or the user is banned.
   - **Private channels**: Require explicit invitation via MLS Add.
3. The hosting node responds with `Accept` or `Reject`.
4. On acceptance, the hosting node begins forwarding channel activities to the remote node's inbox.

### 4.7 Defederation

Any node MAY defederate from any other node at any time. Defederation is immediate and unilateral:

1. The defederating node stops all outbound message delivery to the target node.
2. The defederating node rejects all inbound activities from the target node with HTTP `403 Forbidden`.
3. The defederating node MAY send a `Reject` activity to the target node indicating defederation, though the target node is not required to process it.
4. The defederating node MAY remove cached remote content originating from the target node.

Defederation does not require the consent or acknowledgment of the target node. Nodes SHOULD log defederation events for operator review.

To re-federate after defederation, the full handshake (Section 4.5) MUST be repeated.

---

## 5. Message Envelope

The message envelope defines the exact set of fields that accompany every message, both for local delivery (within a node) and federated delivery (between nodes). The envelope is designed for metadata minimization: it contains only what is necessary for delivery, ordering, and authentication.

### 5.1 Included Fields

Every Cairn message envelope MUST contain the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | URI (UUID-based) | Globally unique identifier for the message. MUST be a URI containing a v4 UUID. |
| `author` | URI | ActivityPub actor URI of the message author. For federated display, this resolves to `username@domain`. |
| `channelId` | URI | URI of the channel this message belongs to. |
| `content` | String or null | Plaintext message content for public channels. MUST be `null` for encrypted channels. Content MUST conform to the formatting rules in Section 9. |
| `encryptedContent` | String or null | Base64url-encoded ciphertext for encrypted channels. MUST be `null` for public channels. See Section 6 for the encrypted payload structure. |
| `nonce` | String or null | Base64url-encoded 24-byte nonce for XChaCha20-Poly1305 decryption. MUST accompany `encryptedContent`. |
| `mlsEpoch` | Integer or null | MLS epoch number under which the message was encrypted. MUST be present for MLS-encrypted messages. |
| `hlcTimestamp` | Object | Hybrid Logical Clock timestamp for causal ordering. Structure: `{ "wall": <int64_ms>, "counter": <uint32>, "node": "<domain>" }`. |
| `signature` | String | Base64url-encoded Ed25519 signature over the canonical form of the message (see Section 5.3). |
| `protocolVersion` | String | Protocol version string (semver). MUST be `"0.1.0"` for this version of the spec. |

### 5.2 Explicitly Excluded Fields

The following fields MUST NOT be included in the message envelope, either locally or across federation boundaries. Implementations MUST strip these fields before federation delivery. Implementations MUST NOT store or transmit these fields as part of the message record.

| Excluded Field | Rationale |
|---------------|-----------|
| **IP address** | Reveals the physical location of the sender. Not necessary for message delivery or ordering. |
| **Device fingerprint** | Reveals information about the sender's hardware and software environment. Not necessary for protocol operation. |
| **Client version** | Reveals information about the sender's software. Can be used for targeted attacks against known vulnerabilities. |
| **User agent string** | Same rationale as client version. |
| **Read receipt status** | Reveals the sender's engagement patterns. Read receipts are opt-in and transmitted via a separate, non-persistent mechanism (never embedded in the message). |
| **Typing indicators** | Ephemeral events that MUST NOT be persisted or federated. Local-only, transmitted via WebSocket and discarded immediately. |
| **Internal database IDs** | Implementation-specific identifiers that could leak information about the node's internal state. Only URIs are used for external identification. |
| **Geographic location** | Never collected, never transmitted. |
| **Delivery timestamps** | The time a message was received by a remote node is local metadata and MUST NOT be federated back to the originating node. |

### 5.3 Canonical Form and Signature

To produce the message signature, implementations MUST construct a canonical byte string from the message fields in the following deterministic order:

```
canonical = id || author || channelId || content_or_ciphertext || hlc_wall || hlc_counter || hlc_node || protocolVersion
```

Where:
- `||` denotes byte concatenation.
- String values are encoded as UTF-8 bytes prefixed by their 4-byte big-endian length.
- Integer values are encoded as 8-byte big-endian integers.
- `content_or_ciphertext` is the `content` field if present, otherwise the raw bytes of `encryptedContent` (before base64url encoding).
- Null values are encoded as a 4-byte zero length prefix with no payload bytes.

The canonical byte string is signed with the author's Ed25519 private key:

```
signature = Ed25519_Sign(author_private_key, canonical)
```

Receiving nodes MUST verify the signature by reconstructing the canonical form and verifying against the author's known public key. Messages with invalid signatures MUST be rejected.

### 5.4 JSON Schema

The following JSON Schema defines the message envelope:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://cairn.chat/schemas/message-envelope/0.1.0",
  "title": "Cairn Message Envelope",
  "description": "The canonical message format for the Cairn protocol v0.1.0",
  "type": "object",
  "required": [
    "id",
    "author",
    "channelId",
    "content",
    "hlcTimestamp",
    "signature",
    "protocolVersion"
  ],
  "properties": {
    "id": {
      "type": "string",
      "format": "uri",
      "description": "Globally unique message URI containing a v4 UUID"
    },
    "author": {
      "type": "string",
      "format": "uri",
      "description": "ActivityPub actor URI of the message author"
    },
    "channelId": {
      "type": "string",
      "format": "uri",
      "description": "URI of the parent channel"
    },
    "content": {
      "type": ["string", "null"],
      "description": "Plaintext content (public channels) or null (encrypted channels)"
    },
    "encryptedContent": {
      "type": ["string", "null"],
      "description": "Base64url-encoded ciphertext for encrypted channels"
    },
    "nonce": {
      "type": ["string", "null"],
      "description": "Base64url-encoded 24-byte nonce for XChaCha20-Poly1305",
      "pattern": "^[A-Za-z0-9_-]{32}$"
    },
    "mlsEpoch": {
      "type": ["integer", "null"],
      "minimum": 0,
      "description": "MLS epoch number"
    },
    "inReplyTo": {
      "type": ["string", "null"],
      "format": "uri",
      "description": "URI of the parent message for threads"
    },
    "hlcTimestamp": {
      "type": "object",
      "required": ["wall", "counter", "node"],
      "properties": {
        "wall": {
          "type": "integer",
          "description": "Wall clock time in milliseconds since Unix epoch"
        },
        "counter": {
          "type": "integer",
          "minimum": 0,
          "description": "Logical counter for same-wall-time ordering"
        },
        "node": {
          "type": "string",
          "description": "Domain name of the originating node"
        }
      },
      "additionalProperties": false
    },
    "signature": {
      "type": "string",
      "description": "Base64url-encoded Ed25519 signature over the canonical message form"
    },
    "protocolVersion": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$",
      "description": "Semantic version of the protocol"
    }
  },
  "additionalProperties": false,
  "if": {
    "properties": {
      "content": { "type": "null" }
    }
  },
  "then": {
    "required": ["encryptedContent", "nonce"]
  }
}
```

### 5.5 Ordering

Messages are ordered by their HLC timestamps. The ordering algorithm is:

1. Compare `hlcTimestamp.wall` values. Lower wall time comes first.
2. If `wall` values are equal, compare `hlcTimestamp.counter` values. Lower counter comes first.
3. If both `wall` and `counter` are equal, compare `hlcTimestamp.node` values lexicographically. Lower node name comes first.

This produces a total order that is consistent across all nodes in the federation. Clients MUST use this ordering when displaying messages.

---

## 6. End-to-End Encryption

Cairn uses layered end-to-end encryption:

- **DMs**: X3DH key agreement followed by the Double Ratchet algorithm.
- **Private group channels**: MLS (Messaging Layer Security, [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420)).
- **Symmetric cipher**: XChaCha20-Poly1305 for all message encryption.

The server MUST NOT have access to plaintext content of encrypted messages at any point. The server acts as a relay and storage service for ciphertext only. This property MUST hold even if the server is compromised.

### 6.1 Cryptographic Primitives

| Function | Algorithm | Reference |
|----------|-----------|-----------|
| Identity keys | Ed25519 | [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032) |
| Key agreement (DMs) | X25519 | [RFC 7748](https://www.rfc-editor.org/rfc/rfc7748) |
| Key agreement (groups) | MLS DHKEM(X25519) | [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420) |
| Symmetric encryption | XChaCha20-Poly1305 | [draft-irtf-cfrg-xchacha](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha) |
| Hash function | SHA-256 | [RFC 6234](https://www.rfc-editor.org/rfc/rfc6234) |
| KDF | HKDF-SHA-256 | [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869) |
| Key derivation (backup) | Argon2id | [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106) |
| Digital signatures | Ed25519 | [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032) |
| MLS ciphersuite | MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519 | [RFC 9420, Section 17.1](https://www.rfc-editor.org/rfc/rfc9420#section-17.1) |

Implementations MUST use well-tested cryptographic libraries (e.g., libsodium, OpenMLS). Implementations MUST NOT implement cryptographic primitives from scratch.

### 6.2 Key Bundles

Each user generates the following key material on first registration (or on first login from a new device):

#### Identity Key

- **Algorithm**: Ed25519
- **Lifetime**: Long-term (persists for the lifetime of the account)
- **Purpose**: Signs prekeys, authenticates the user in MLS groups, and provides a stable public identity
- **Storage**: Private key stored in OS keychain (desktop/mobile) or encrypted IndexedDB (web)

#### Signed Prekey

- **Algorithm**: X25519
- **Lifetime**: Medium-term (rotated every 7-30 days)
- **Purpose**: Used in X3DH key agreement for DM initiation
- **Signature**: Signed by the identity key to bind it to the user's identity
- **Rotation**: Client generates a new signed prekey periodically and uploads the public half to the server. The old signed prekey is retained briefly to handle in-flight messages.

#### One-Time Prekeys

- **Algorithm**: X25519
- **Lifetime**: Single-use (consumed on retrieval)
- **Purpose**: Provide forward secrecy in X3DH by ensuring each session uses unique keying material
- **Batch size**: Client uploads 50 one-time prekeys initially. When the server-side count drops below 10, the client replenishes to 50.

#### Key Bundle Upload

The client uploads the public portions of all keys to the server:

```
POST /api/v1/users/me/keys
Content-Type: application/json

{
  "identity_key": "<base64url-encoded Ed25519 public key>",
  "signed_prekey": {
    "key_id": 1,
    "public_key": "<base64url-encoded X25519 public key>",
    "signature": "<base64url-encoded Ed25519 signature over the prekey>"
  },
  "one_time_prekeys": [
    {
      "key_id": 100,
      "public_key": "<base64url-encoded X25519 public key>"
    },
    {
      "key_id": 101,
      "public_key": "<base64url-encoded X25519 public key>"
    }
  ]
}
```

#### Key Bundle Retrieval

When initiating a DM, the client fetches the recipient's key bundle:

```
GET /api/v1/users/:user_id/keys
```

For **cross-instance DMs**, the initiator's instance fetches the recipient's key bundle from the recipient's home instance via federation:

```
GET /api/v1/federation/users/:did/keys
```

This endpoint is authenticated via HTTP Signatures (node-to-node) and returns the same key bundle format. The `:did` parameter is the recipient's `did:cairn:...` identifier.

**Response:**

```json
{
  "identity_key": "<base64url-encoded Ed25519 public key>",
  "signed_prekey": {
    "key_id": 1,
    "public_key": "<base64url-encoded X25519 public key>",
    "signature": "<base64url-encoded Ed25519 signature over the prekey>"
  },
  "one_time_prekey": {
    "key_id": 100,
    "public_key": "<base64url-encoded X25519 public key>"
  }
}
```

The server MUST return exactly one one-time prekey and MUST remove it from storage after retrieval (single-use guarantee). If no one-time prekeys are available, the `one_time_prekey` field MUST be `null` and the X3DH handshake proceeds without it (reduced forward secrecy for the initial message).

### 6.3 X3DH for DMs

The Extended Triple Diffie-Hellman (X3DH) protocol is used to establish a shared secret between two users who may not both be online. The protocol follows the Signal specification with the following parameters:

- **Curve**: X25519
- **Hash**: SHA-256
- **Info string**: `"cairn-x3dh-v1"`

#### Protocol Steps

**Alice** wants to send a DM to **Bob**.

1. Alice fetches Bob's key bundle from the server (identity key `IK_B`, signed prekey `SPK_B`, one-time prekey `OPK_B`).
2. Alice verifies the signature on `SPK_B` using `IK_B`.
3. Alice generates an ephemeral X25519 key pair `(EK_A_priv, EK_A_pub)`.
4. Alice computes four DH values:
   - `DH1 = X25519(IK_A_priv_x25519, SPK_B)` -- Alice's identity key (converted to X25519) with Bob's signed prekey
   - `DH2 = X25519(EK_A_priv, IK_B_x25519)` -- Alice's ephemeral key with Bob's identity key (converted to X25519)
   - `DH3 = X25519(EK_A_priv, SPK_B)` -- Alice's ephemeral key with Bob's signed prekey
   - `DH4 = X25519(EK_A_priv, OPK_B)` -- Alice's ephemeral key with Bob's one-time prekey (if available)
5. Alice computes the shared secret: `SK = HKDF(DH1 || DH2 || DH3 || DH4, salt=0, info="cairn-x3dh-v1")`, truncated to 32 bytes.
6. Alice initializes the Double Ratchet with `SK` and sends the initial message containing:
   - Alice's identity public key `IK_A`
   - Alice's ephemeral public key `EK_A_pub`
   - The ID of Bob's signed prekey used (`SPK_B.key_id`)
   - The ID of Bob's one-time prekey used (`OPK_B.key_id`, if applicable)
   - The ciphertext of the first message

Bob, upon receiving the initial message, recomputes the same four DH values using his private keys and derives the same shared secret `SK`, then initializes his side of the Double Ratchet.

### 6.4 Double Ratchet for DMs

After the X3DH handshake, ongoing DM messages use the Double Ratchet algorithm for forward secrecy and break-in recovery.

- **KDF chain**: HKDF-SHA-256
- **Symmetric encryption**: XChaCha20-Poly1305
- **DH ratchet**: X25519 key pairs rotated on each round-trip

The Double Ratchet provides:

1. **Forward secrecy**: Compromising the current key does not reveal past messages.
2. **Break-in recovery**: Even if a session key is compromised, future messages are protected after a DH ratchet step.
3. **Out-of-order tolerance**: Each message includes a chain index so messages received out of order can be decrypted correctly (up to a configurable window, default: 1000 skipped message keys).

### 6.5 MLS for Group Channels

Private group channels use the Messaging Layer Security protocol ([RFC 9420](https://www.rfc-editor.org/rfc/rfc9420)). MLS provides efficient group key management with O(log n) cost for membership changes.

#### MLS Ciphersuite

Cairn implementations MUST support the following MLS ciphersuite:

```
MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519
```

This ciphersuite uses:
- **HPKE KEM**: DHKEM(X25519, HKDF-SHA256)
- **HPKE KDF**: HKDF-SHA256
- **HPKE AEAD**: AES-128-GCM
- **Hash**: SHA-256
- **Signature**: Ed25519

Implementations MAY support additional ciphersuites. When multiple ciphersuites are available, the group creator selects the ciphersuite and all members MUST support it.

#### MLS Credentials

Each user's Ed25519 identity key serves as their MLS `BasicCredential`. No additional key types are required. The mapping is:

```
User Ed25519 Identity Key --> MLS BasicCredential --> MLS LeafNode
```

#### KeyPackages

MLS KeyPackages are pre-computed tokens that allow a user to be added to a group. They are analogous to one-time prekeys in X3DH.

- Client generates a batch of 50 KeyPackages and uploads them to the server.
- Each KeyPackage is single-use: once claimed by another user for a group Add operation, it is removed from the server.
- When the count drops below 10, the client replenishes to 50.

**KeyPackage endpoints:**

```
POST /api/v1/users/me/key-packages       -- Upload batch of KeyPackages
GET  /api/v1/users/:id/key-packages      -- Claim one KeyPackage (consumed)
GET  /api/v1/users/me/key-packages/count  -- Check remaining count
```

The server stores KeyPackages as opaque blobs. The server MUST NOT inspect or modify KeyPackage contents.

#### Group Lifecycle

**Creation:**

1. User creates a private channel via the API.
2. Client creates a new MLS group locally (user is the sole initial member).
3. Client uploads the initial `GroupInfo` to the server.
4. Group ID maps 1:1 to the channel UUID.

**Adding a member:**

1. Inviter fetches the invitee's KeyPackage from the server.
2. Inviter creates an MLS `Add` proposal and `Commit` locally.
3. Inviter submits the `Commit` to the server.
4. Server distributes the `Welcome` message to the new member.
5. Server distributes the `Commit` to all existing members.
6. All members advance to the new epoch.
7. New member processes the `Welcome` and gains access to messages from this point forward.

**Removing a member:**

1. An authorized user (channel owner, moderator, or the member themselves) creates an MLS `Remove` proposal and `Commit`.
2. `Commit` is submitted to the server and distributed to remaining members.
3. All remaining members advance to the new epoch with a new group key.
4. The removed member's client deletes its local group state.
5. Forward secrecy: the removed member MUST NOT be able to decrypt messages sent after removal.

**MLS delivery endpoints:**

```
POST /api/v1/channels/:id/mls/commit    -- Submit MLS Commit
POST /api/v1/channels/:id/mls/proposal  -- Submit MLS Proposal
POST /api/v1/channels/:id/mls/welcome   -- Submit MLS Welcome
GET  /api/v1/channels/:id/mls/messages  -- Fetch pending MLS handshake messages
```

All MLS protocol messages are stored and relayed as opaque blobs. The server is a "dumb pipe" for MLS -- it MUST NOT interpret, modify, or make access control decisions based on MLS message contents.

#### Epoch Management

- Each Add, Remove, or Update operation advances the epoch counter.
- Clients retain keys for recent epochs (default: last 10 epochs) to decrypt late-arriving messages.
- Messages include the `mlsEpoch` field so the recipient knows which key to use.
- Old epoch keys are deleted after the retention window expires, providing forward secrecy for older messages.

### 6.6 Encrypted Payload Structure

All encrypted message payloads (both DM and MLS) follow this structure before base64url encoding:

```
+----------------+---------------------------+-----+
| Header (5 B)   | Ciphertext (variable)     | Tag |
+----------------+---------------------------+-----+

Header:
  - Version byte (1 byte): 0x01 for this protocol version
  - Encryption type (1 byte):
      0x01 = X3DH/Double Ratchet (DM)
      0x02 = MLS (group channel)
  - Reserved (3 bytes): must be 0x000000

Ciphertext:
  - XChaCha20-Poly1305 encrypted plaintext
  - The nonce (24 bytes) is transmitted separately in the message envelope

Tag:
  - Poly1305 authentication tag (16 bytes, appended by XChaCha20-Poly1305)
```

The plaintext before encryption is structured as:

```json
{
  "type": "text",
  "body": "The actual message content",
  "attachments": [
    {
      "type": "file",
      "name": "photo.jpg",
      "size": 245760,
      "content_hash": "sha256:a1b2c3d4...",
      "encryption_key": "<base64url-encoded file encryption key>",
      "encryption_nonce": "<base64url-encoded file nonce>"
    }
  ],
  "mentions": [
    {
      "type": "user",
      "id": "https://node-a.example.com/users/bob",
      "offset": 0,
      "length": 4
    }
  ]
}
```

For encrypted file attachments, the file is encrypted client-side with a random key before upload. The encryption key and nonce are included in the encrypted message payload so only channel members can decrypt the file.

### 6.7 Key Backup and Recovery

Users MAY back up their private key material to the server in encrypted form:

1. Client serializes all private keys (identity key, signed prekey, one-time prekeys, MLS group states, Double Ratchet sessions) into a binary blob.
2. Client derives an encryption key from a user-provided backup passphrase using Argon2id:
   - Memory: 256 MiB
   - Iterations: 3
   - Parallelism: 4
   - Salt: 32 random bytes (stored alongside the encrypted backup)
   - Output: 32-byte key
3. Client encrypts the blob with XChaCha20-Poly1305 using the derived key.
4. Client uploads the encrypted blob to the server.

The server stores the backup as an opaque blob. It MUST NOT be able to decrypt the backup without the user's passphrase.

**Backup endpoints:**

```
POST   /api/v1/users/me/key-backup  -- Upload encrypted backup
GET    /api/v1/users/me/key-backup  -- Retrieve encrypted backup
DELETE /api/v1/users/me/key-backup  -- Delete backup
```

---

## 7. Privacy Manifest

Each Cairn node MUST publish a privacy manifest -- a machine-readable JSON document describing the node's data handling practices. This manifest is used during federation handshakes (Section 4.5) to allow nodes to evaluate each other's privacy posture and for users to make informed decisions about joining federated channels.

### 7.1 Endpoint

The privacy manifest MUST be served at:

```
GET /.well-known/privacy-manifest
```

The response MUST have `Content-Type: application/json`. The endpoint MUST NOT require authentication. A copy of the manifest is also included inline in the `/.well-known/cairn-federation` response (Section 4.2).

### 7.2 Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://cairn.chat/schemas/privacy-manifest/1.0",
  "title": "Cairn Privacy Manifest",
  "description": "Machine-readable privacy policy for a Cairn node",
  "type": "object",
  "required": ["version", "logging", "retention", "federation"],
  "properties": {
    "version": {
      "type": "string",
      "const": "1.0",
      "description": "Privacy manifest schema version"
    },
    "logging": {
      "type": "object",
      "required": ["ip_addresses", "message_content", "federation_metadata"],
      "properties": {
        "ip_addresses": {
          "type": "boolean",
          "description": "Whether the node logs user IP addresses"
        },
        "message_content": {
          "type": "boolean",
          "description": "Whether the node logs public message content (encrypted content is never logged)"
        },
        "federation_metadata": {
          "type": "boolean",
          "description": "Whether the node logs federation-related metadata (remote node IPs, request headers)"
        },
        "access_logs": {
          "type": "boolean",
          "description": "Whether the node retains HTTP access logs"
        },
        "access_log_retention_hours": {
          "type": "integer",
          "minimum": 0,
          "description": "Hours that access logs are retained before deletion. 0 means logs are not kept."
        }
      },
      "additionalProperties": false
    },
    "retention": {
      "type": "object",
      "required": ["messages_days", "files_days"],
      "properties": {
        "messages_days": {
          "type": "integer",
          "minimum": 0,
          "description": "Days that messages are retained. 0 means indefinite retention."
        },
        "files_days": {
          "type": "integer",
          "minimum": 0,
          "description": "Days that uploaded files are retained. 0 means indefinite retention."
        },
        "audit_log_days": {
          "type": "integer",
          "minimum": 0,
          "description": "Days that audit/moderation logs are retained"
        },
        "inactive_account_days": {
          "type": "integer",
          "minimum": 0,
          "description": "Days after which inactive accounts may be purged. 0 means accounts are never purged."
        }
      },
      "additionalProperties": false
    },
    "federation": {
      "type": "object",
      "required": ["metadata_stripped", "read_receipts"],
      "properties": {
        "metadata_stripped": {
          "type": "boolean",
          "description": "Whether the node strips metadata (IP, user agent, etc.) from federated activities"
        },
        "read_receipts": {
          "type": "boolean",
          "description": "Whether the node sends read receipts across federation boundaries"
        },
        "open_federation": {
          "type": "boolean",
          "description": "Whether the node accepts federation requests from any node (true) or only allowlisted nodes (false)"
        }
      },
      "additionalProperties": false
    },
    "legal": {
      "type": "object",
      "properties": {
        "jurisdiction": {
          "type": "string",
          "description": "Legal jurisdiction under which this node operates (ISO 3166-1 alpha-2 country code)"
        },
        "privacy_policy_url": {
          "type": "string",
          "format": "uri",
          "description": "URL to the human-readable privacy policy"
        },
        "terms_of_service_url": {
          "type": "string",
          "format": "uri",
          "description": "URL to the terms of service"
        },
        "data_request_contact": {
          "type": "string",
          "description": "Email address for GDPR/data deletion requests"
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

### 7.3 Example

```json
{
  "version": "1.0",
  "logging": {
    "ip_addresses": false,
    "message_content": false,
    "federation_metadata": false,
    "access_logs": true,
    "access_log_retention_hours": 48
  },
  "retention": {
    "messages_days": 365,
    "files_days": 90,
    "audit_log_days": 730,
    "inactive_account_days": 0
  },
  "federation": {
    "metadata_stripped": true,
    "read_receipts": false,
    "open_federation": true
  },
  "legal": {
    "jurisdiction": "DE",
    "privacy_policy_url": "https://node-a.example.com/privacy",
    "terms_of_service_url": "https://node-a.example.com/terms",
    "data_request_contact": "privacy@node-a.example.com"
  }
}
```

### 7.4 Validation During Federation

When establishing federation (Section 4.5, step 5), a node MAY evaluate the remote node's privacy manifest against configurable minimum requirements. Example policy rules:

- REJECT if `logging.ip_addresses` is `true`
- REJECT if `logging.message_content` is `true`
- REJECT if `federation.metadata_stripped` is `false`
- WARN if `retention.messages_days` exceeds local policy
- WARN if `federation.read_receipts` is `true`

Operators configure these rules locally. There are no global mandatory rules -- each node exercises sovereignty over its federation decisions.

### 7.5 Manifest Freshness

Nodes SHOULD re-fetch the privacy manifests of their federated peers periodically (RECOMMENDED: once every 24 hours). If a peer's manifest changes in a way that violates the local node's policy, the node SHOULD notify the operator and MAY automatically defederate.

---

## 8. Protocol Versioning

### 8.1 Version Format

The Cairn protocol uses [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH
```

- **MAJOR**: Incremented for breaking changes that are not backwards compatible. Nodes on different major versions MUST NOT federate.
- **MINOR**: Incremented for new features that are backwards compatible. Nodes on different minor versions within the same major version SHOULD be able to federate, with the newer node gracefully degrading features the older node does not support.
- **PATCH**: Incremented for bug fixes and clarifications that do not change protocol behavior.

The current protocol version is `0.1.0`.

While the major version is `0`, the protocol is considered unstable. Minor version increments MAY include breaking changes. Implementors SHOULD expect rapid iteration during the `0.x` phase.

### 8.2 Version Advertisement

Every node advertises its protocol version in two places:

1. **`/.well-known/cairn-federation`**: The `protocol_version` field contains the node's current (preferred) version. The `supported_versions` array lists all versions the node can operate with.

2. **Message envelope**: Every message includes a `protocolVersion` field (Section 5.1).

### 8.3 Version Negotiation

During federation handshake (Section 4.5), nodes negotiate a common protocol version:

1. Node A reads Node B's `supported_versions` array.
2. Node A computes the intersection with its own `supported_versions`.
3. If the intersection is empty, federation MUST be rejected with a clear error:
   ```json
   {
     "error": "protocol_version_mismatch",
     "message": "No common protocol version. Local supports: [0.1.0]. Remote supports: [0.2.0].",
     "local_versions": ["0.1.0"],
     "remote_versions": ["0.2.0"]
   }
   ```
4. If the intersection is non-empty, both nodes use the highest common version for all subsequent communication.

### 8.4 Backwards Compatibility

Implementations MUST maintain backwards compatibility with at least the previous **2 minor versions** within the same major version. For example, a node implementing version `1.4.0` MUST also support versions `1.3.x` and `1.2.x`.

When communicating with a node on an older minor version:

- The newer node MUST NOT send activities containing features introduced after the negotiated version.
- The newer node MUST gracefully handle the absence of fields that were added in newer versions.
- Unknown fields in received activities MUST be ignored (not rejected).

### 8.5 Deprecation Policy

When a protocol version is scheduled for deprecation:

1. The deprecation MUST be announced at least **2 minor versions** in advance. For example, version `1.2.0` can be deprecated no earlier than version `1.4.0`.
2. During the deprecation period, nodes supporting the deprecated version SHOULD include a `Deprecation` header in federation responses:
   ```
   Deprecation: version="0.1.0"; sunset="2027-06-01"; successor="0.3.0"
   ```
3. After the sunset date, nodes MAY drop support for the deprecated version.

### 8.6 Version in Activities

All federated activities MUST include the protocol version in the JSON-LD context or as a top-level property. Receiving nodes use this to determine how to parse the activity:

```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://cairn.chat/ns/v1"
  ],
  "protocolVersion": "0.1.0",
  "type": "Create",
  "..."
}
```

If the `protocolVersion` field is missing, the receiving node SHOULD assume the oldest supported version and process the activity on a best-effort basis.

---

## 9. Message Formatting

Cairn messages support a safe subset of Markdown for text formatting, along with mentions and emoji. Clients MUST render formatted content according to this section. Servers MUST NOT modify message content beyond what is described in Section 9.5 (sanitization).

### 9.1 Markdown Subset

The following Markdown constructs MUST be supported:

| Syntax | Rendered As | Example |
|--------|------------|---------|
| `**text**` | **Bold** | `**important**` |
| `*text*` or `_text_` | *Italic* | `*emphasis*` |
| `~~text~~` | ~~Strikethrough~~ | `~~deleted~~` |
| `` `text` `` | `Inline code` | `` `variable` `` |
| ` ```lang\ncode\n``` ` | Code block with syntax highlighting | See below |
| `[text](url)` | Hyperlink | `[Cairn](https://cairn.chat)` |
| `> text` | Blockquote | `> quoted text` |
| `- item` or `* item` | Unordered list | `- first item` |
| `1. item` | Ordered list | `1. first item` |
| `||text||` | Spoiler (hidden until clicked) | `||spoiler content||` |

**Code blocks:**

````
```elixir
defmodule Hello do
  def world, do: "Hello, world!"
end
```
````

Clients SHOULD provide syntax highlighting for code blocks when a language hint is present. The language hint is the text immediately after the opening triple backtick.

**Constructs that are NOT supported:**

- Headings (`#`, `##`, etc.)
- Horizontal rules (`---`)
- Tables
- Images via Markdown syntax (images are sent as file attachments)
- HTML (see Section 9.5)
- Footnotes
- Definition lists

### 9.2 Mentions

#### User Mentions (Local)

Local user mentions use the `@username` syntax:

```
Hey @alice, can you review this?
```

Clients MUST resolve `@username` against the local node's user list and render it as an interactive element (clickable to view profile).

#### User Mentions (Federated)

Federated user mentions use the `@username@domain` syntax:

```
Thanks @bob@node-b.example.com for the feedback!
```

Clients MUST render federated mentions with the full `username@domain` identifier and SHOULD make them clickable to view the remote user's profile.

#### Channel Mentions

Channel mentions use the `#channel-name` syntax:

```
Please move this discussion to #off-topic.
```

Clients MUST resolve `#channel-name` against the current server's channel list and render it as an interactive element (clickable to navigate to the channel).

#### Mention Encoding in Message Content

Mentions are encoded inline in the message `content` field using their display syntax (`@alice`, `@bob@node.com`, `#general`). The encrypted payload structure (Section 6.6) includes a `mentions` array that maps each mention to its canonical URI and position within the text. This allows clients to render mentions correctly even if the display name changes.

### 9.3 Emoji

#### Unicode Emoji

Unicode emoji are included directly in the message content. Clients MUST render Unicode emoji using the platform's native emoji rendering or a bundled emoji font.

#### Shortcodes

Emoji shortcodes use the `:name:` syntax:

```
Great work! :thumbsup: :tada:
```

Clients MUST maintain a mapping of shortcodes to Unicode emoji and resolve them during rendering. The shortcode mapping MUST include at minimum all emoji defined in [Unicode CLDR short names](https://cldr.unicode.org/translation/characters-emoji-symbols/emoji-names).

Shortcodes are replaced with their Unicode equivalent during rendering, not during transmission. The raw shortcode text is transmitted in the message content to preserve editability.

#### Custom Emoji

Custom server emoji use the same `:name:` syntax with a server-specific namespace:

```
This is cool :server_custom_emoji:
```

Custom emoji are out of scope for protocol version `0.1.0` and will be defined in a future version.

### 9.4 URL Handling

URLs in message content SHOULD be automatically detected and rendered as clickable hyperlinks, even without explicit Markdown link syntax. URL detection MUST use a standard URL parser and MUST NOT rely on regular expressions alone.

URL preview (link unfurling) is OPTIONAL and MUST be performed client-side. Servers MUST NOT fetch URLs on behalf of users to generate previews (this leaks user activity to the server). Clients that implement URL preview SHOULD:

1. Only fetch previews for URLs from well-known, trusted domains.
2. Respect `robots.txt` and `X-Robots-Tag` headers.
3. Allow users to disable URL previews globally or per-channel.
4. MUST NOT send cookies, authentication headers, or referrer information when fetching previews.

### 9.5 Sanitization Rules

Implementations MUST enforce the following sanitization rules on message content before rendering:

1. **No raw HTML.** Any HTML tags in message content MUST be escaped (e.g., `<script>` becomes `&lt;script&gt;`). This applies to both plaintext and Markdown-rendered content.

2. **No `javascript:` URIs.** Links with `javascript:` scheme MUST be stripped or rejected. This includes all case variants (`JavaScript:`, `jAvAsCrIpT:`, etc.) and URL-encoded forms (`%6A%61%76%61%73%63%72%69%70%74%3A`).

3. **No `data:` URIs in links.** The `data:` URI scheme MUST NOT be allowed in hyperlinks. (Data URIs for inline images in client-rendered content are a client implementation decision and are not governed by this spec.)

4. **No `vbscript:` URIs.** Same treatment as `javascript:`.

5. **Scheme allowlist for links.** Hyperlinks (both explicit Markdown and auto-detected) MUST only use the following schemes: `https`, `http`, `mailto`, `tel`, `cairn` (protocol-specific deep links). All other schemes MUST be rejected or rendered as plain text.

6. **Maximum message length.** Messages MUST NOT exceed 4000 Unicode codepoints for the `content` field. Implementations SHOULD reject longer messages at the API level.

7. **Maximum code block length.** Individual code blocks MUST NOT exceed 20,000 characters. Longer code blocks MUST be truncated at rendering time or rejected at the API level.

8. **Mention injection prevention.** Mention resolution (`@username`, `#channel`) MUST only resolve against known entities. Unresolved mentions MUST be rendered as plain text.

9. **Unicode normalization.** Implementations SHOULD normalize message content to NFC (Canonical Decomposition followed by Canonical Composition) before storage. This prevents homoglyph attacks and ensures consistent text matching.

10. **Bidirectional text control.** Unicode bidirectional override characters (U+202A through U+202E, U+2066 through U+2069) MUST be stripped from message content to prevent text spoofing attacks.

---

## 10. Appendices

### Appendix A: Hybrid Logical Clock Algorithm

The Hybrid Logical Clock (HLC) provides causal ordering of events across distributed nodes without requiring synchronized clocks. The algorithm is based on [Kulkarni et al., 2014](https://cse.buffalo.edu/tech-reports/2014-04.pdf).

#### Data Structure

```
HLC {
  wall: int64    -- Physical wall-clock time in milliseconds since Unix epoch
  counter: uint32  -- Logical counter for events at the same wall time
  node: string   -- Domain name of the node that generated this timestamp
}
```

#### Algorithm Pseudocode

```
// State: each node maintains a local HLC

function hlc_init(node_domain):
  return HLC {
    wall: physical_clock_ms(),
    counter: 0,
    node: node_domain
  }

// Called when a local event occurs (e.g., a user sends a message)
function hlc_now(local_hlc):
  now = physical_clock_ms()
  if now > local_hlc.wall:
    local_hlc.wall = now
    local_hlc.counter = 0
  else:
    local_hlc.counter = local_hlc.counter + 1
  return copy(local_hlc)

// Called when a remote event is received (e.g., a federated message arrives)
function hlc_update(local_hlc, remote_hlc):
  now = physical_clock_ms()

  if now > local_hlc.wall AND now > remote_hlc.wall:
    local_hlc.wall = now
    local_hlc.counter = 0
  else if local_hlc.wall == remote_hlc.wall:
    local_hlc.counter = max(local_hlc.counter, remote_hlc.counter) + 1
  else if local_hlc.wall > remote_hlc.wall:
    local_hlc.counter = local_hlc.counter + 1
  else:  // remote_hlc.wall > local_hlc.wall
    local_hlc.wall = remote_hlc.wall
    local_hlc.counter = remote_hlc.counter + 1
  return copy(local_hlc)

// Comparison: total order over HLC values
function hlc_compare(a, b):
  if a.wall != b.wall:
    return compare(a.wall, b.wall)
  if a.counter != b.counter:
    return compare(a.counter, b.counter)
  return compare(a.node, b.node)  // lexicographic tiebreak
```

#### Drift Protection

To prevent a malfunctioning or malicious node from advancing the HLC arbitrarily far into the future, implementations MUST enforce a maximum drift limit:

```
MAX_DRIFT_MS = 60000  // 1 minute

function hlc_update_safe(local_hlc, remote_hlc):
  now = physical_clock_ms()
  if remote_hlc.wall - now > MAX_DRIFT_MS:
    reject("Remote HLC wall time too far in the future")
  return hlc_update(local_hlc, remote_hlc)
```

Messages with HLC timestamps that exceed the drift limit MUST be rejected by the receiving node.

---

### Appendix B: HTTP Message Signatures (RFC 9421)

Cairn uses [RFC 9421 (HTTP Message Signatures)](https://www.rfc-editor.org/rfc/rfc9421) for authenticating federated HTTP requests. This replaces the deprecated `draft-cavage-http-signatures`.

#### Signing Parameters

| Parameter | Value |
|-----------|-------|
| Algorithm | `ed25519` |
| Key ID | Node's public key fingerprint: `SHA-256(public_key_bytes)` truncated to 16 bytes, hex-encoded |
| Covered components | `@method`, `@target-uri`, `@authority`, `content-type`, `content-digest`, `date` |
| Signature validity | 300 seconds (5 minutes) from `date` header |

#### Signing Process

1. Construct the signature base string per RFC 9421 Section 2.5:
   ```
   "@method": POST
   "@target-uri": https://node-b.example.com/inbox
   "@authority": node-b.example.com
   "content-type": application/activity+json
   "content-digest": sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:
   "date": Tue, 09 Feb 2026 14:30:00 GMT
   "@signature-params": ("@method" "@target-uri" "@authority" "content-type" "content-digest" "date");created=1739108400;keyid="a1b2c3d4e5f6a7b8";alg="ed25519"
   ```

2. Sign the base string with the node's Ed25519 private key.

3. Include the signature in the `Signature` and `Signature-Input` headers:
   ```http
   POST /inbox HTTP/1.1
   Host: node-b.example.com
   Date: Tue, 09 Feb 2026 14:30:00 GMT
   Content-Type: application/activity+json
   Content-Digest: sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:
   Signature-Input: cairn=("@method" "@target-uri" "@authority" "content-type" "content-digest" "date");created=1739108400;keyid="a1b2c3d4e5f6a7b8";alg="ed25519"
   Signature: cairn=:bWVzc2FnZSBzaWduYXR1cmUgZXhhbXBsZQ==:
   ```

#### Verification Process

1. Receiving node extracts the `Signature-Input` header to determine covered components and key ID.
2. Receiving node looks up the public key for the given `keyid` (from cached federation data or by fetching `/.well-known/cairn-federation`).
3. Receiving node reconstructs the signature base string from the request.
4. Receiving node verifies the Ed25519 signature against the reconstructed base string.
5. Receiving node checks that the `date` header is within 300 seconds of the current time (replay protection).
6. Receiving node checks that the `content-digest` matches the actual request body.

If any verification step fails, the request MUST be rejected with HTTP `401 Unauthorized`.

#### Content-Digest

All POST requests to federated endpoints MUST include a `Content-Digest` header per [RFC 9530](https://www.rfc-editor.org/rfc/rfc9530):

```
Content-Digest: sha-256=:base64-encoded-sha256-of-request-body:
```

This binds the signature to the request body, preventing body tampering attacks.

---

### Appendix C: Supported Ciphersuites

#### MLS Ciphersuites

| Ciphersuite | Status | Notes |
|------------|--------|-------|
| `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` | **REQUIRED** | Mandatory-to-implement per RFC 9420. MUST be supported by all implementations. |
| `MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519` | RECOMMENDED | Uses ChaCha20-Poly1305 instead of AES-GCM. Preferred on platforms without hardware AES acceleration. |

Implementations MUST support the REQUIRED ciphersuite. Implementations SHOULD support the RECOMMENDED ciphersuite. When creating a new MLS group, the group creator selects the ciphersuite. All members added to the group MUST support the selected ciphersuite.

#### Symmetric Encryption

| Algorithm | Key Size | Nonce Size | Tag Size | Usage |
|-----------|----------|------------|----------|-------|
| XChaCha20-Poly1305 | 256 bits | 192 bits (24 bytes) | 128 bits (16 bytes) | Message content encryption (DMs and MLS application messages) |
| AES-128-GCM | 128 bits | 96 bits (12 bytes) | 128 bits (16 bytes) | MLS tree operations (within the MLS ciphersuite) |
| AES-256-GCM | 256 bits | 96 bits (12 bytes) | 128 bits (16 bytes) | Key backup encryption (alternative to XChaCha20-Poly1305) |

XChaCha20-Poly1305 is the primary symmetric cipher for application-layer message encryption because:

1. It has a 192-bit nonce, making random nonce collisions negligible even at high message volumes.
2. It does not require hardware acceleration for fast performance (important for mobile and web clients).
3. It is available in all target cryptographic libraries (libsodium, Web Crypto via polyfill, ring).

#### Key Agreement

| Algorithm | Usage |
|-----------|-------|
| X25519 (ECDH) | X3DH key agreement for DMs, MLS DHKEM |
| HKDF-SHA-256 | Key derivation from shared secrets |

#### Digital Signatures

| Algorithm | Usage |
|-----------|-------|
| Ed25519 | Node identity keys, user identity keys, message signatures, HTTP Message Signatures, MLS credentials |

#### Password/Passphrase Hashing

| Algorithm | Usage | Parameters |
|-----------|-------|------------|
| Argon2id | Account password hashing | Memory: 64 MiB, Iterations: 3, Parallelism: 4 |
| Argon2id | Key backup passphrase KDF | Memory: 256 MiB, Iterations: 3, Parallelism: 4 |

The higher memory parameter for key backup derivation is intentional: key backups are decrypted infrequently, and the higher cost provides better resistance against offline brute-force attacks on the backup passphrase.

---

### Appendix D: Wire Format Summary

This appendix provides a quick reference for all endpoints and their wire formats.

#### Well-Known Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| GET | `/.well-known/cairn-federation` | `application/json` | No |
| GET | `/.well-known/webfinger` | `application/jrd+json` | No |
| GET | `/.well-known/privacy-manifest` | `application/json` | No |
| GET | `/.well-known/did/:did` | `application/json` | No |

#### ActivityPub Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| POST | `/inbox` | `application/activity+json` | HTTP Signature |
| POST | `/users/:id/inbox` | `application/activity+json` | HTTP Signature |
| GET | `/users/:id/outbox` | `application/activity+json` | No (public only) |
| GET | `/users/:id` | `application/activity+json` | No (public profile) |

#### Key Management Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| POST | `/api/v1/users/me/keys` | `application/json` | JWT |
| GET | `/api/v1/users/:id/keys` | `application/json` | JWT |
| POST | `/api/v1/users/me/key-packages` | `application/json` | JWT |
| GET | `/api/v1/users/:id/key-packages` | `application/json` | JWT |
| GET | `/api/v1/users/me/key-packages/count` | `application/json` | JWT |
| POST | `/api/v1/users/me/key-backup` | `application/octet-stream` | JWT |
| GET | `/api/v1/users/me/key-backup` | `application/octet-stream` | JWT |
| DELETE | `/api/v1/users/me/key-backup` | -- | JWT |

#### Identity Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| POST | `/api/v1/users/me/did/rotate-signing-key` | `application/json` | JWT |
| POST | `/api/v1/federation/auth-token` | `application/json` | JWT |

#### Federated Access Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| POST | `/api/v1/federated/join/:server_id` | `application/json` | Federated Token |
| GET | `/api/v1/federated/servers/:id/channels` | `application/json` | Federated Token |
| POST | `/api/v1/federated/invites/:code/use` | `application/json` | Federated Token |

#### Cross-Instance DM Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| GET | `/api/v1/federation/users/:did/keys` | `application/json` | HTTP Signature |
| POST | `/api/v1/dm/federated` | `application/json` | JWT |
| GET | `/api/v1/dm/requests` | `application/json` | JWT |
| GET | `/api/v1/dm/requests/sent` | `application/json` | JWT |
| POST | `/api/v1/dm/requests/:id/respond` | `application/json` | JWT |
| POST | `/api/v1/dm/requests/:id/block` | `application/json` | JWT |

#### MLS Delivery Endpoints

| Method | Path | Content-Type | Auth Required |
|--------|------|-------------|---------------|
| POST | `/api/v1/channels/:id/mls/commit` | `application/octet-stream` | JWT |
| POST | `/api/v1/channels/:id/mls/proposal` | `application/octet-stream` | JWT |
| POST | `/api/v1/channels/:id/mls/welcome` | `application/octet-stream` | JWT |
| GET | `/api/v1/channels/:id/mls/messages` | `application/json` | JWT |

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| `0.1.0` | 2026-02-09 | Initial draft specification |
| `0.1.1` | 2026-02-11 | Added `did:cairn` portable identity (Section 4.1.1), federated auth tokens, DID operation chain, DM guard, ActivityPub DID extension fields (`cairn:did`, `cairn:homeInstance`, `cairn:channelId`, `cairn:displayName`), federated access endpoints, WebFinger DID resolution |
| `0.1.2` | 2026-02-11 | Cross-instance encrypted DMs: `Invite`/`cairn:DmHint` activity type (Section 3.7), federated key bundle endpoint (`GET /api/v1/federation/users/:did/keys`), DM request endpoints, consent-first DM flow, anti-spam (rate limits, DID block list) |

---

## References

- [ActivityPub](https://www.w3.org/TR/activitypub/) -- W3C Recommendation
- [Activity Streams 2.0](https://www.w3.org/TR/activitystreams-core/) -- W3C Recommendation
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) -- Key words for use in RFCs
- [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869) -- HKDF
- [RFC 6234](https://www.rfc-editor.org/rfc/rfc6234) -- SHA-256
- [RFC 7033](https://www.rfc-editor.org/rfc/rfc7033) -- WebFinger
- [RFC 7748](https://www.rfc-editor.org/rfc/rfc7748) -- X25519
- [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032) -- Ed25519
- [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106) -- Argon2
- [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420) -- Messaging Layer Security (MLS)
- [RFC 9421](https://www.rfc-editor.org/rfc/rfc9421) -- HTTP Message Signatures
- [RFC 9530](https://www.rfc-editor.org/rfc/rfc9530) -- Content-Digest
- [Semantic Versioning 2.0.0](https://semver.org/)
- [Kulkarni et al., "Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases", 2014](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
- [XChaCha20-Poly1305](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha)
- [Signal X3DH Specification](https://signal.org/docs/specifications/x3dh/)
- [Signal Double Ratchet Specification](https://signal.org/docs/specifications/doubleratchet/)
