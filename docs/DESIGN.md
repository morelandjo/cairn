# Murmuring Design Document

> **Audience:** Developers, security researchers, technically curious users
> **Status:** Phases 0–9 complete · AGPL-3.0 · ~25 min read
>
> This document explains *how and why* Murmuring is built the way it is. For
> wire formats and crypto details see the [Protocol Specification](./protocol-spec.md).
> For attack surfaces and trust boundaries see the [Threat Model](./security/threat-model.md).
> For running a server see [SERVER.md](./SERVER.md). For client usage see [CLIENT.md](./CLIENT.md).

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Design Philosophy](#2-design-philosophy)
3. [Architecture Overview](#3-architecture-overview)
4. [The Untrusted Server Model](#4-the-untrusted-server-model)
5. [Encryption Architecture](#5-encryption-architecture)
6. [Federation](#6-federation)
7. [Portable Identity — did:murmuring](#7-portable-identity--didmurmuring)
8. [Voice and Video](#8-voice-and-video)
9. [Data Model](#9-data-model)
10. [Client Architecture](#10-client-architecture)
11. [Operational Architecture](#11-operational-architecture)
12. [How Murmuring Compares](#12-how-murmuring-compares)
13. [Known Limitations and Future Work](#13-known-limitations-and-future-work)
14. [Appendix: Document Map](#appendix-document-map)

---

## 1. Introduction

Murmuring is a privacy-first federated communication platform. Think Discord's
guild-and-channel model — servers, roles, categories, voice, bots — but
federated like email and end-to-end encrypted by default. No single company
controls the network. No server operator can read your private messages.

The project started from a question: *What if the server didn't need to be
trusted?* Every design decision flows from that constraint. Encryption happens
in the client. The server stores and forwards ciphertext it cannot decrypt.
Federation lets independent instances interoperate while retaining sovereignty.
A self-certifying identity (`did:murmuring`) means your account belongs to you,
not to whoever runs the server.

This document is the map between those principles and the code that implements
them. It intentionally avoids duplicating wire formats and byte layouts covered
in the [Protocol Specification](./protocol-spec.md), and attack-surface
analysis covered in the [Threat Model](./security/threat-model.md). When you
need that level of detail, follow the cross-references.

---

## 2. Design Philosophy

Five principles guide every design decision in Murmuring. They are ordered by
priority — when two principles conflict, the higher one wins.

### 2.1 Untrusted Server

The server is an adversary by default. It faithfully routes ciphertext, manages
membership, and enforces rate limits, but it never sees plaintext for private
content. This isn't paranoia — it's an engineering constraint that simplifies the
trust model. Users don't need to evaluate whether an operator is trustworthy.
The protocol makes the question irrelevant for message content.

### 2.2 No Centralization

There is no "Murmuring Inc." running a blessed instance. Anyone can run a
server. Instances federate with each other voluntarily. If an instance
disappears, its users' identities survive (see [§7](#7-portable-identity--didmurmuring)).
If an instance behaves badly, other instances can defederate from it. The
network has no single point of failure or control.

### 2.3 Privacy as a Protocol Requirement

Privacy isn't a feature flag — it's baked into the wire format. DMs use X3DH
key agreement and Double Ratchet encryption. Group channels use MLS (RFC 9420).
Voice frames are encrypted with AES-128-GCM via Insertable Streams before the
SFU ever sees them. Even key backups are encrypted with a passphrase-derived key
the server never learns.

The one deliberate exception is public channels. When a user creates a public
channel, they are making an informed choice to share content in the clear. The
server indexes public channel messages for search. Everything else — DMs,
private channels, voice, key material — is opaque ciphertext from the server's
perspective.

### 2.4 Federation with Sovereignty

Federation means instances can exchange messages across organizational
boundaries. Sovereignty means each instance controls who it federates with, what
metadata it shares, and what content policies it enforces. A privacy manifest
(published at a well-known endpoint) advertises each instance's data practices.
Defederation is a first-class operation: one API call severs the link cleanly.

### 2.5 Metadata Minimization

Even when the server must see metadata to function (membership lists, channel
types, timestamps), Murmuring minimizes what crosses federation boundaries.
Federated messages are stripped of internal IDs, IP addresses, and
server-specific context before delivery. Hybrid Logical Clocks provide causal
ordering without leaking wall-clock precision.

---

## 3. Architecture Overview

Murmuring is a monorepo with six backend services, four client targets, and a
shared protocol package.

```
┌─────────────────────────────────────────────────────────────────┐
│                          Clients                                │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────────┐  │
│  │   Web   │  │ Desktop  │  │  Mobile  │  │  Bots/Webhooks  │  │
│  │ (React) │  │ (Tauri)  │  │ (Expo)   │  │   (HTTP API)    │  │
│  └────┬────┘  └────┬─────┘  └────┬─────┘  └───────┬─────────┘  │
│       └─────┬──────┴─────────────┘                 │            │
│         ┌───┴───┐                                  │            │
│         │ proto │  (types, crypto, API client)      │            │
│         └───┬───┘                                  │            │
└─────────────┼──────────────────────────────────────┼────────────┘
              │ HTTPS / WSS                          │ HTTPS
┌─────────────┼──────────────────────────────────────┼────────────┐
│             ▼                                      ▼            │
│  ┌──────────────────┐    Bearer token    ┌─────────────────┐    │
│  │  Phoenix Server  │◄─────────────────► │   SFU (media)   │    │
│  │   (port 4000)    │                    │   (port 4001)   │    │
│  └──┬───┬───┬───┬───┘                    └────────┬────────┘    │
│     │   │   │   │                                 │             │
│     ▼   ▼   ▼   ▼                                 ▼             │
│  ┌────┐┌─────┐┌───────────┐┌───────┐       ┌──────────┐        │
│  │ PG ││Redis││Meilisearch││ Oban  │       │  coturn  │        │
│  └────┘└─────┘└───────────┘└───────┘       │  (TURN)  │        │
│                                            └──────────┘        │
│                          Backend                                │
└─────────────────────────────────────────────────────────────────┘
```

### Components

**Phoenix Server** (`server/`) — The main application. Handles authentication,
channels, messaging, roles, permissions, federation, file uploads, search,
moderation, and WebSocket connections. Written in Elixir on Phoenix Framework.
This is the only component clients connect to for non-media traffic.

**SFU** (`sfu/`) — A Selective Forwarding Unit for voice and video. Built on
Fastify and mediasoup. Receives encrypted media frames from clients and
forwards them to other participants without decrypting. Authenticates with the
Phoenix server via a shared-secret Bearer token.

**PostgreSQL** — Primary data store for users, servers, channels, messages,
roles, DID operations, federation state, and audit logs.

**Redis** — Ephemeral state: session tokens, rate limiter counters, transient
caches. Named `:murmuring_redis` in the supervision tree.

**Meilisearch** — Full-text search engine. Indexes only public channel messages.
Private and DM content never reaches Meilisearch.

**coturn** — TURN relay for NAT traversal. Issues HMAC-SHA1 short-lived
credentials (12-hour TTL) so clients behind restrictive firewalls can establish
WebRTC connections.

**Proto** (`proto/`) — Shared TypeScript package consumed by all client targets.
Contains type definitions, the `ApiClient` class (transport-agnostic, automatic
token refresh on 401), all crypto primitives (X3DH, Double Ratchet, MLS via
WASM, voice encryption), and API function modules. Proto is the security
boundary — crypto operations never leave this package.

### Supervision Tree

The Phoenix server starts its OTP supervision tree in this order (`:one_for_one`
strategy):

1. `MurmuringWeb.Telemetry` — telemetry reporters
2. `Murmuring.PromEx` — Prometheus metrics (conditionally started)
3. `Murmuring.Repo` — Ecto database connection pool
4. `Oban` — background job processor
5. `Redix` — Redis connection (named `:murmuring_redis`)
6. `Murmuring.Auth.PasswordValidator` — password strength GenServer
7. `Murmuring.RateLimiter` — API rate limiter state
8. `MurmuringWeb.Plugs.RateLimiter` — HTTP rate limiter plug
9. `DNSCluster` — DNS-based node clustering
10. `Phoenix.PubSub` — pub/sub for real-time broadcasts
11. `MurmuringWeb.Presence` — online/typing presence tracking
12. `MurmuringWeb.Endpoint` — HTTP/WebSocket endpoint

When federation is enabled, two additional children are appended:

13. `Murmuring.Federation.NodeIdentity` — Ed25519 keypair GenServer
14. `Murmuring.Federation.HLC` — Hybrid Logical Clock

The `:one_for_one` strategy means a crashed child restarts independently without
affecting siblings. This matters for federation: if `NodeIdentity` crashes and
restarts, the HTTP endpoint and all existing WebSocket connections continue
serving requests.

---

## 4. The Untrusted Server Model

The core design bet of Murmuring is that users should not need to trust server
operators with their private content. This section makes the trust boundary
explicit.

### What the Server CAN See

| Data | Why |
|------|-----|
| Usernames and email addresses | Registration and login |
| Server/channel membership | Routing messages to the right channels |
| Channel types (public, private, DM) | Determining whether to index for search |
| Message timestamps and sizes | Storage and ordering |
| File sizes and MIME types | Storage quotas and content-type headers |
| Voice channel participation | SFU room management |
| Federation metadata | Routing between instances |
| IP addresses | TCP connections (mitigated by Tor/VPN) |

### What the Server CANNOT See

| Data | Why |
|------|-----|
| Private channel message content | MLS-encrypted; server stores opaque blobs |
| DM content | X3DH + Double Ratchet encrypted end-to-end |
| Voice/video frames | AES-128-GCM encrypted via Insertable Streams before reaching SFU |
| MLS group state | Clients manage all MLS state locally |
| Key backup contents | Encrypted with passphrase-derived key (Argon2id + XChaCha20-Poly1305) |
| Encryption keys | Never leave the client (or proto package) |
| Search queries for private content | Private content is never indexed |

### Design Decisions That Follow

**MLS as opaque blobs.** The server stores MLS welcome messages, key packages,
and commits as binary blobs. It doesn't parse them, validate them, or know which
ciphersuite is in use. This means the server can't selectively drop key updates
or inject fake members without clients detecting the inconsistency via MLS's
built-in transcript consistency checks.

**Search only indexes public channels.** Meilisearch receives plaintext only
from channels explicitly marked as public by server administrators. Private
channel content never touches the search index — the server literally doesn't
have the plaintext to index.

**File encryption keys travel inside encrypted messages.** When a user uploads a
file in a private channel, the file is encrypted client-side. The decryption key
is included in the MLS-encrypted message payload. The server stores the
encrypted file and the encrypted message but cannot connect the decryption key
to the file.

**Key backups are doubly opaque.** Users can back up their encryption keys to the
server, but the backup is encrypted with a passphrase-derived key using Argon2id
(high memory parameters) and XChaCha20-Poly1305. The server stores a blob it
cannot decrypt. Even a compromised database dump yields nothing without the
user's passphrase.

### Contrast with Other Platforms

**Discord** has full access to all message content, files, and voice streams.
**Matrix** encrypts rooms with Megolm but the homeserver sees room metadata and
can be configured to log decrypted content. **Signal** encrypts everything but
doesn't support servers/guilds or federation. Murmuring sits at the intersection:
guild-style organization, federation, and an encryption model where the server
is genuinely excluded from content access.

---

## 5. Encryption Architecture

Murmuring uses three distinct encryption protocols, each chosen for its
properties in a specific context. For wire formats and byte layouts, see the
[Protocol Specification §6](./protocol-spec.md#6-end-to-end-encryption).

### 5.1 Key Hierarchy

Every user has two long-lived key pairs:

- **Signing key** — Used for day-to-day E2EE operations: signing messages,
  participating in MLS groups, generating ephemeral keys. Can be rotated without
  changing identity.
- **Rotation key** — Used exclusively for identity operations: signing DID
  operation log entries that update the signing key or other identity metadata.
  This is the "key to the keys" and should be kept offline when not in use.

Below these sit ephemeral keys: signed pre-keys (rotated periodically),
one-time pre-keys (consumed on first contact), and MLS epoch secrets (rotated
on every group membership change).

### 5.2 DMs: X3DH + Double Ratchet

Direct messages use the same protocol family as Signal: Extended Triple
Diffie-Hellman (X3DH) for initial key agreement, followed by the Double Ratchet
for ongoing message encryption.

**Why X3DH?** It provides forward secrecy from the first message, even when the
recipient is offline. The sender combines their ephemeral key with the
recipient's pre-published key bundle (identity key + signed pre-key + one-time
pre-key) to derive a shared secret without real-time interaction.

**Why Double Ratchet?** It provides both forward secrecy (compromising today's
key doesn't reveal yesterday's messages) and post-compromise security
(the ratchet "heals" after a key compromise once both parties send new
messages). Each message uses a unique key derived from the ratchet state.

The server sees DM ciphertext and metadata (sender, recipient, timestamp) but
never the plaintext. DMs are also never federated via ActivityPub — they travel
only between the two participants' clients and the hosting instance (see
[§6.5](#65-cross-instance-dms)).

### 5.3 Groups: MLS (RFC 9420)

Group channels (including private channels in servers) use the Messaging Layer
Security protocol. Murmuring uses the `openmls` library compiled to WASM
(see [ADR: MLS Library Choice](./decisions/mls-library.md)).

**Why MLS over Sender Keys?** Signal's Sender Keys (used by WhatsApp and
Matrix's Megolm) require O(n) work to add or remove a member — every existing
member must be individually notified. MLS uses a tree structure (TreeKEM) that
reduces this to O(log n). For a 1,000-member channel, that's the difference
between 1,000 operations and 10.

**Ciphersuite:** `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` — the same
curve used for Murmuring identity keys, avoiding a second key type.

**Lifecycle:** A user creates an MLS group when they create a private channel.
Adding a member generates a Welcome message (encrypted to the new member's key
package) and a Commit (updating the group's epoch secret). Removing a member
generates a Commit that rotates the epoch secret, ensuring the removed member
cannot decrypt future messages. All MLS state lives in the client; the server
stores and forwards binary blobs without parsing them.

**WASM boundary:** The `openmls` crate is compiled to WASM and loaded in the
proto package. All MLS state is serialized to bytes on the TypeScript side —
there is no hidden WASM-side state. This makes state management predictable and
debuggable, and means the WASM module can be unloaded and reloaded without
losing group state.

### 5.4 Voice: Insertable Streams + AES-128-GCM

Voice and video frames are encrypted before they reach the SFU, using the
browser's Insertable Streams API (or `RTCRtpScriptTransform` on Safari).

**Pipeline:**
1. MLS epoch secret for the voice channel → HKDF → AES-128-GCM key
2. Sender encrypts each frame: `[12-byte IV][ciphertext][16-byte GCM tag]`
3. Encrypted frame is sent to the SFU via WebRTC
4. SFU forwards the opaque frame to other participants (it cannot decrypt)
5. Receivers derive the same key from their MLS state and decrypt

**Automatic key rotation:** When a participant joins or leaves the voice
channel, MLS generates a new epoch. All participants derive a new voice key from
the new epoch secret. There is a brief transition period where receivers accept
both the old and new key.

**Platform limits:** Insertable Streams require Chrome, Edge, or Safari 15.4+.
Desktop (Tauri) support depends on the underlying webview — full on Windows
(Chromium WebView2), partial on macOS (WebKit), unavailable on Linux (WebKitGTK).
Mobile (React Native) lacks Insertable Streams entirely. See
[ADR: WebRTC Platform Matrix](./decisions/webrtc-webview-matrix.md) for the
full compatibility table. When E2E voice encryption is unavailable, voice still
works — it's just encrypted only on the DTLS-SRTP transport layer (SFU can see
frames).

### 5.5 Key Backup

Users can back up their encryption keys (signing key, MLS group states, ratchet
states) to the server for recovery on a new device.

**Encryption:** Passphrase → Argon2id (high memory: 256 MB, 3 iterations) →
XChaCha20-Poly1305. The high Argon2id parameters make offline brute-force
attacks against a stolen database dump impractical. XChaCha20-Poly1305 provides
authenticated encryption with a 192-bit nonce, eliminating nonce-reuse concerns.

The server stores the encrypted backup blob. It cannot decrypt it, and it cannot
tell whether a restore attempt uses the correct passphrase — only the client
knows if decryption succeeded.

---

## 6. Federation

Federation lets independent Murmuring instances exchange messages across
organizational boundaries. For wire-level details, see the
[Protocol Specification §4](./protocol-spec.md#4-federation-handshake).

### 6.1 Node Identity

Every instance has an Ed25519 key pair generated on first boot and stored on
disk. The public key is published at `/.well-known/murmuring-federation` along
with the instance domain and protocol version. This key signs all outgoing
federation HTTP requests and all federated authentication tokens.

**Key rotation** is supported with a 7-day grace period: the old key is
published alongside the new one, and remote instances accept signatures from
either key during the transition.

### 6.2 Handshake

Federation between two instances starts with a Follow/Accept handshake:

1. Instance A sends a Follow activity to Instance B's inbox
2. Instance B validates A's node identity via well-known endpoint
3. Instance B evaluates A's privacy manifest against its own federation policy
4. If acceptable, Instance B sends an Accept activity back to A
5. Both instances record the federation relationship

Privacy manifests (published at `/.well-known/murmuring-privacy`) declare each
instance's data retention, logging, and sharing practices. An instance can
require that federation peers meet minimum privacy standards before accepting
the handshake.

### 6.3 Message Delivery

Federated messages are delivered as ActivityPub activities to each instance's
`/inbox` endpoint. Every request is signed with HTTP Message Signatures
(RFC 9421) using the sending instance's Ed25519 key.

**Metadata stripping:** Before a message crosses a federation boundary,
internal IDs, IP addresses, and server-specific metadata are removed. The
receiving instance sees only the minimum needed to display the message:
content (ciphertext for private channels), author DID, channel ID, and an HLC
timestamp.

**Async delivery:** Federation messages are delivered via Oban background jobs
with exponential backoff. If a remote instance is temporarily unreachable,
messages queue and retry automatically. This decouples federation reliability
from real-time performance.

**Ordering:** Hybrid Logical Clocks (HLC) provide causal ordering across
instances without requiring synchronized wall clocks. Each message carries an
HLC timestamp that combines a physical component with a logical counter,
ensuring consistent ordering even when clocks drift.

### 6.4 Defederation

An administrator can defederate from another instance with a single API call.
This immediately stops delivering messages to that instance, stops accepting
messages from it, and removes its users from local servers. Defederation is a
sovereignty tool — it lets each instance operator decide who they trust.

### 6.5 Cross-Instance DMs

DMs between users on different instances follow the "initiator hosts" model:

1. Alice (on instance A) wants to DM Bob (on instance B)
2. The DM channel is created on Alice's instance (A)
3. A lightweight "DM hint" is sent to Bob via federation — this tells Bob that
   Alice wants to chat, but contains no message content
4. Bob's client connects to Alice's instance via federated auth to join the
   DM channel
5. All DM messages live on instance A, encrypted end-to-end between Alice and Bob

**Critical privacy property:** DM message content never crosses federation
boundaries via ActivityPub. The hint only tells Bob to connect. Instance B never
sees the DM ciphertext. This is enforced at the protocol level — the
`dm_channel?/1` check prevents DM channels from being included in any
federation outbox.

---

## 7. Portable Identity — did:murmuring

### 7.1 The Problem

In centralized platforms, the service owns your identity. Delete your Discord
account and your username, history, and connections disappear. In traditional
federated systems (email, Mastodon), your identity is bound to your instance —
`alice@mastodon.social` stops working if mastodon.social goes down.

Murmuring needed an identity system that is:
- Self-certifying (no authority can revoke it)
- Instance-independent (survives server shutdown)
- Key-rotatable (compromised keys don't mean a new identity)
- Verifiable by anyone (no phone-home to resolve)

### 7.2 How It Works

A `did:murmuring` identifier is derived from the SHA-256 hash of the genesis
operation, encoded in base58:

```
did:murmuring:7Kf3x...  ← base58(SHA-256(genesis_op))
```

The genesis operation contains the user's initial signing key and rotation key.
Because the DID is derived from this operation's hash, it is stable — it never
changes, even when keys are rotated.

**Operation chain:** Every identity change (key rotation, metadata update) is
recorded as a new operation that references the hash of the previous operation,
forming a hash chain. Each operation is signed by the rotation key. Anyone can
verify the chain by:

1. Fetching the operation log from any instance that has it
2. Verifying each operation's signature against the rotation key active at that point
3. Confirming the hash chain is unbroken
4. Confirming the DID matches the genesis operation's hash

This makes identity verification fully decentralized. No instance needs to be
"authoritative" — the math is the authority.

### 7.3 What It Enables

**Remote server join:** Alice's DID lives on instance A, but she can join a
server on instance B. Instance B fetches her DID operation chain, verifies it,
and issues a federated auth token signed by B's node key. Alice's client
connects to B via WebSocket using this token.

**Key rotation without identity change:** If Alice's signing key is compromised,
she uses her rotation key to sign a new operation that publishes a new signing
key. Her DID stays the same. Old messages signed with the compromised key remain
valid (they were valid at the time). New messages use the new key.

**Federated auth tokens:** A compact `base64url(payload).base64url(signature)`
token where the payload contains the user's DID and the signature is the
remote instance's Ed25519 node key. This lets the remote instance authenticate
Alice without calling back to her home instance on every request.

### 7.4 Instance Loss

If Alice's home instance disappears:

- **DID remains valid.** Any instance that cached her operation chain can still
  verify her identity.
- **Remote memberships continue.** Servers she joined on other instances still
  have her federated user record.
- **DMs hosted on the lost instance are gone.** The ciphertext lived on that
  server. This is a known trade-off of the "initiator hosts" model.
- **She cannot join new servers** until she registers on a new home instance and
  publishes her DID there.

Future work includes a migration protocol that lets users move their home
instance without losing continuity.

---

## 8. Voice and Video

### 8.1 Why SFU

Three architectures were considered for multi-party voice:

| Architecture | Scales | Encrypt E2E | Server CPU |
|---|---|---|---|
| Mesh (peer-to-peer) | O(n²) connections | Yes | None |
| MCU (mixing) | O(n) connections | No (must decode) | High |
| SFU (forwarding) | O(n) connections | Yes (forwards opaque) | Low |

SFU is the clear winner for Murmuring's threat model. It scales linearly,
doesn't need to decode media (preserving E2E encryption), and requires minimal
server CPU. The trade-off is slightly higher bandwidth than MCU (each
participant receives n-1 streams instead of one mixed stream), but modern
codecs and simulcast mitigate this.

### 8.2 Architecture

```
Client A ──► Phoenix Server ──► SFU (mediasoup) ──► Client B
  │          (signaling)        (media relay)          │
  │                                                    │
  └────────────── coturn (TURN relay) ─────────────────┘
                  (NAT traversal)
```

1. Client A joins a voice channel via Phoenix WebSocket (signaling)
2. Phoenix creates a room on the SFU via authenticated HTTP
3. SFU returns WebRTC transport parameters to the client
4. Client establishes WebRTC connection (directly or via coturn TURN relay)
5. Client produces encrypted media streams; SFU forwards to consumers
6. When a client leaves, Phoenix signals the SFU to clean up

The Phoenix server handles all signaling logic (join, leave, mute, permissions).
The SFU handles only media forwarding. This separation means the SFU is
stateless with respect to application logic — it doesn't know about channels,
roles, or permissions.

### 8.3 E2E Encryption

Voice encryption derives from the MLS group:

1. Channel's MLS epoch secret → HKDF with context `"murmuring-voice-v1"` →
   128-bit AES key
2. Each audio/video frame is encrypted:
   `[IV: 12 bytes][AES-128-GCM ciphertext][authentication tag: 16 bytes]`
3. IV increments per frame (monotonic counter) to prevent nonce reuse
4. When MLS epoch changes (member join/leave), a new key is derived

The SFU forwards these encrypted frames without modification. It cannot
distinguish speech from silence, video from screenshare, or one speaker from
another at the content level.

### 8.4 Platform Support

| Platform | Voice/Video | E2E Encryption | Notes |
|---|---|---|---|
| Chrome / Edge | Full | Full | Insertable Streams API |
| Safari 15.4+ | Full | Full | RTCRtpScriptTransform |
| Desktop (Windows) | Full | Full | Chromium WebView2 |
| Desktop (macOS) | Full | Partial | WebKit WKWebView |
| Desktop (Linux) | Full | No | WebKitGTK lacks Insertable Streams |
| Mobile (iOS/Android) | Voice only | No | react-native-webrtc, no Insertable Streams |

When E2E encryption is unavailable, the client displays a warning indicator.
Voice still works — it's protected by DTLS-SRTP on the transport layer, but the
SFU can see the unencrypted frames.

---

## 9. Data Model

### 9.1 Core Entities

```
┌──────────┐     ┌──────────┐     ┌───────────┐     ┌─────────┐
│   User   │────►│  Server  │────►│  Channel  │────►│ Message │
│          │     │ (Guild)  │     │           │     │         │
│ - email  │     │ - name   │     │ - name    │     │ - body  │
│ - handle │     │ - owner  │     │ - type    │     │ - nonce │
└────┬─────┘     └────┬─────┘     │ - server  │     └────┬────┘
     │                │           └───────────┘          │
     │                ▼                                  │
     │           ┌──────────┐                            │
     │           │   Role   │     ┌───────────────┐      │
     │           │ - perms  │     │ FederatedUser │◄─────┘
     │           └──────────┘     │ - did         │
     │                            │ - actor_uri   │
     ▼                            └───────────────┘
┌──────────┐     ┌───────────────┐
│   DID    │     │  KeyBundle    │
│ Document │     │ - identity_key│
│ - ops[]  │     │ - signed_pre  │
└──────────┘     │ - one_time[]  │
                 └───────────────┘
```

### 9.2 Server/Guild Model

A Server (called "guild" in some contexts) is the top-level organizational unit.
Everything is scoped to a server: channels, roles, categories, invites,
moderation actions. A user can be a member of many servers. A server can have
many channels organized into categories.

Channels have a type: `public` (content visible to server members, indexed for
search), `private` (MLS-encrypted, invisible to non-members), `voice` (media
channels), or `dm` (direct messages between two users, scoped outside of any
server).

### 9.3 Dual-Author Model

Messages can come from local users or federated users. Rather than forcing
federated users into the local user table, the schema uses two foreign keys:

- `author_id` → `users` table (local user)
- `federated_author_id` → `federated_users` table (remote user)

Exactly one is set per message. Queries use a LEFT JOIN on both to resolve the
author regardless of origin:

```sql
SELECT m.*, u.handle AS local_author, fu.display_name AS federated_author
FROM messages m
LEFT JOIN users u ON m.author_id = u.id
LEFT JOIN federated_users fu ON m.federated_author_id = fu.id
```

This avoids polluting the user table with phantom records for remote users
while keeping message queries simple.

### 9.4 Permission Resolution

Permissions resolve in a specific order, where later rules override earlier ones:

1. **Server owner** — full permissions, cannot be overridden
2. **@everyone role** — baseline permissions for all server members
3. **Role permissions** — computed by OR-ing all of a user's role permissions together; explicit denies win over grants across roles
4. **Channel overrides** — per-role permission overrides scoped to a specific channel
5. **User overrides** — per-user permission overrides scoped to a specific channel

This mirrors Discord's permission model, which users already understand. The
layered approach means administrators can set broad defaults at the server level
and fine-tune per channel.

---

## 10. Client Architecture

### 10.1 Proto Package

The `proto/` package is the shared foundation for all clients. It exports:

- **Types** — `MessageEnvelope`, `KeyBundle`, `DIDDocument`, `VoiceState`, and
  all other shared type definitions
- **Constants** — protocol version, namespace URIs, limits, ciphersuites
- **Crypto** — `generateIdentityKeyPair`, `x3dhInitiate`/`x3dhRespond`,
  `DoubleRatchet` class, `encryptMessage`/`decryptMessage`, voice key derivation
- **MLS** — `MlsClient` class wrapping openmls WASM, `exportKeys`/`importKeys`
- **ApiClient** — transport-agnostic HTTP client with automatic token refresh on
  401 responses. Uses `FetchTransport` by default but accepts any transport
  implementing the `ApiTransport` interface
- **API modules** — `authApi`, `channelsApi`, `serversApi`, `moderationApi`,
  `voiceApi`, `identityApi`, `federationApi`, and others

Proto has two package exports: `.` (everything) and `./api` (API subpath only).
Crypto operations never leave this package — clients call proto functions, not
raw WebCrypto APIs.

### 10.2 Web

The web client (`client/web/`) is a React application built with Vite. State
management uses Zustand stores. Real-time communication uses Phoenix WebSocket
channels. Voice uses mediasoup-client.

In production, the SPA is served directly by Phoenix (configured via
`config :murmuring, :serve_spa, true`). A catch-all route serves `index.html`
for client-side routing. Server configuration is injected via
`window.__MURMURING_CONFIG__` at serve time.

### 10.3 Desktop

The desktop app (`client/desktop/`) uses Tauri v2, which wraps the web client's
built output in a native window. Platform-specific features include:

- **Keychain storage** — encryption keys stored in the OS keychain instead of
  localStorage
- **System tray** — background operation with notification badges
- **Keyboard shortcuts** — OS-native shortcut registration
- **Auto-update** — built-in update mechanism
- **Deep linking** — `murmuring://` protocol handler

Tauri APIs are accessed via dynamic imports to avoid bundling Tauri-specific
code in web builds. The `keyStorage.ts` module provides a unified interface that
uses the keychain on desktop and falls back to localStorage on web.

### 10.4 Mobile

The mobile app (`client/mobile/`) is a separate Expo/React Native codebase
(not the web client in a webview). Key adaptations:

- **Absolute URLs** — React Native doesn't have a browser origin, so all API
  calls use absolute URLs via `getApiBaseUrl()` / `getWsUrl()`
- **Secure storage chunking** — `expo-secure-store` has a 2 KB per-item limit,
  so encryption keys are chunked across multiple items with the same API surface
- **No WASM** — Hermes (RN's JS engine) doesn't support WASM, so MLS E2EE is
  unavailable on mobile. Private channels show a placeholder explaining the
  limitation
- **SQLite offline cache** — `expo-sqlite` stores `cached_messages` and an
  `outbound_queue` for offline-first messaging
- **Biometric auth** — optional fingerprint/face unlock via `expo-local-authentication`
- **Push notifications** — Expo Push API with privacy-first payloads (no message
  content or sender info in the push payload)

### 10.5 Multi-Instance Connections

The `connectionStore` (Zustand) manages simultaneous WebSocket connections to
multiple instances:

```typescript
// Simplified from client/web/src/stores/connectionStore.ts
connections: Map<string, InstanceConnection>

interface InstanceConnection {
  domain: string
  token: string          // JWT (home) or federated auth token (remote)
  socket: PhoenixSocket
  status: "connecting" | "connected" | "disconnected" | "error"
  isHome: boolean
}
```

Each instance gets its own Phoenix Socket with its own authentication token. The
home instance uses a relative WebSocket path (`/socket`), while remote instances
use absolute WSS URLs (`wss://<domain>/socket`). Connection status is reactive —
the UI updates connection indicators in real-time as instances connect and
disconnect.

---

## 11. Operational Architecture

### 11.1 Background Jobs

Oban (PostgreSQL-backed job queue) handles all async work:

| Queue | Jobs |
|-------|------|
| `federation` | ActivityPub delivery with exponential backoff |
| `push` | Push notification dispatch via Expo Push API |
| `default` | Audit log pruning (90-day retention), auto-unban expiry, link preview fetching |

Jobs survive server restarts (persisted in PostgreSQL). Failed federation
deliveries retry with exponential backoff, preventing thundering-herd problems
when a remote instance comes back online.

### 11.2 Observability

**Metrics:** PromEx exposes Prometheus metrics for Phoenix, Ecto, Oban, and
custom application counters. A pre-configured Grafana dashboard provides
visibility into request rates, database performance, job queue depth, and
federation delivery success rates.

**Correlation IDs:** Every HTTP request receives a unique correlation ID
(generated or forwarded from the `X-Request-ID` header). This ID is added to
Logger metadata and included in responses, making it possible to trace a
request across log files.

### 11.3 Security Hardening

- **Rate limiting** — ETS-based per-IP rate limiter at the plug level, plus
  per-user rate limits on sensitive operations (login: 5/min, registration:
  3/hr, WebSocket messages: 10/s, federation inbox: 100/min/node, DM requests:
  10/hr)
- **Registration bot protection** — ALTCHA proof-of-work challenge (SHA-256,
  ~1-2s solve time) plus honeypot field. Privacy-preserving: no third-party
  services or user tracking.
- **Security headers** — CSP, HSTS, X-Frame-Options, X-Content-Type-Options,
  Referrer-Policy applied by `SecurityHeaders` plug
- **Audit logging** — security-relevant events (login, role changes, moderation
  actions, federation events) recorded in `audit_logs` table with 90-day
  retention
- **CI scanning** — Sobelow (Elixir static analysis), npm audit, and cargo
  audit run on every PR

### 11.4 Deployment

Murmuring offers multiple deployment paths:

- **Install script** — single-command automated setup for fresh servers
- **Docker Compose** — `docker-compose.prod.yml` with all six services, volumes,
  and health checks
- **Ansible** — four playbooks (`setup.yml`, `deploy.yml`, `backup.yml`,
  `update.yml`) for managed deployments
- **murmuring-ctl** — CLI tool for common operations (start, stop, update,
  backup, restore, status)

Minimum hardware for a personal instance (up to 10 users): 1 vCPU, 1 GB RAM,
20 GB SSD. See [SERVER.md](./SERVER.md) for full deployment documentation.

---

## 12. How Murmuring Compares

|  | Murmuring | Discord | Matrix | Signal |
|---|---|---|---|---|
| **Federation** | Yes (ActivityPub) | No | Yes (Matrix protocol) | No |
| **E2E Encryption** | Default for DMs/private | No | Opt-in (Megolm) | Default |
| **Self-hosting** | Yes (single command) | No | Yes | Partial (server only) |
| **Portable identity** | Yes (did:murmuring) | No | No (instance-bound) | No (phone-bound) |
| **Open source** | AGPL-3.0 | No | Apache-2.0 | AGPL-3.0 |
| **Guild/server model** | Yes | Yes | Spaces (limited) | No |
| **Voice/video** | SFU + E2E | SFU (no E2E) | Jitsi/Element Call | P2P |
| **Metadata visibility** | Minimized | Full access | Homeserver sees all | Minimal |
| **Group encryption** | MLS (O(log n)) | N/A | Megolm (O(n)) | Sender Keys (O(n)) |
| **Identity tied to** | Cryptographic key | Email/phone | Instance | Phone number |

### Why Not Matrix?

Matrix is the closest existing system to Murmuring's goals. The key differences:

- **MLS vs. Megolm.** Megolm requires O(n) work per membership change. MLS's
  tree structure is O(log n). At scale, this matters.
- **Self-certifying identity.** Matrix identities are instance-bound
  (`@user:server`). If the server goes away, so does the identity. Murmuring's
  DID survives instance loss.
- **Guild model.** Matrix Spaces are bolted on after the fact. Murmuring's
  server/channel/role/category hierarchy is a first-class concept with
  integrated permissions.
- **Untrusted server.** Matrix homeservers can be configured to log decrypted
  content. Murmuring's server never has the keys.

### Why Not Signal?

Signal has excellent encryption but a different scope:

- **No federation.** One organization runs all infrastructure.
- **No guilds.** Signal is for messaging, not community organization.
- **Phone-number identity.** Identity is bound to a phone number, which is
  controlled by telecom carriers.
- **No self-hosting.** You can't run your own Signal server for your community.

### Honest Trade-offs

Murmuring's design has real costs:

- **Complexity.** Three encryption protocols, a DID system, and federation add
  significant implementation and conceptual complexity.
- **Mobile limitations.** No MLS on mobile (Hermes can't run WASM), no E2E
  voice encryption on mobile.
- **No content moderation of encrypted content.** The server can't scan
  encrypted messages for CSAM or other abuse. This is a fundamental tension
  between privacy and safety.
- **Instance dependency for new connections.** While DIDs survive instance loss,
  users need a home instance to join new servers.

---

## 13. Known Limitations and Future Work

**Mobile E2EE.** Hermes (React Native's JavaScript engine) does not support
WebAssembly, which blocks MLS on mobile. Options under investigation include
native MLS bindings via JSI (JavaScript Interface) or a future Hermes WASM
implementation.

**Instance migration.** Users can currently survive instance loss for existing
connections but cannot migrate their home instance. A migration protocol would
let users move their DID's home, transferring key bundles, channel memberships,
and message history.

**Linux desktop voice E2E.** WebKitGTK does not support Insertable Streams.
Until it does, Linux desktop users get voice without end-to-end encryption
(DTLS-SRTP still protects the transport layer).

**CSAM and encrypted content.** The untrusted server model means the server
cannot scan encrypted content for child sexual abuse material. This is a genuine
tension. Potential approaches include client-side scanning (raises other privacy
concerns) or hash-matching against known material databases at the client level.
No solution has been implemented.

**Scale testing.** Murmuring has not been tested beyond small-to-medium
deployments. MLS group operations, federation delivery at scale, and SFU
performance with hundreds of concurrent voice participants need load testing.

**Search privacy.** Currently, only public channel content is searchable. Users
in private channels cannot search their own message history server-side. A
future approach could use client-side indexing or searchable symmetric encryption
to enable private search without exposing content to the server.

---

## Appendix: Document Map

| Document | Purpose |
|----------|---------|
| [`DESIGN.md`](./DESIGN.md) (this file) | Architecture, design rationale, trade-offs |
| [`protocol-spec.md`](./protocol-spec.md) | Wire formats, crypto details, federation handshake steps |
| [`security/threat-model.md`](./security/threat-model.md) | Attack surfaces, trust boundaries, data classification |
| [`decisions/mls-library.md`](./decisions/mls-library.md) | ADR: openmls via WASM for MLS implementation |
| [`decisions/webrtc-webview-matrix.md`](./decisions/webrtc-webview-matrix.md) | ADR: WebRTC platform compatibility |
| [`SERVER.md`](./SERVER.md) | Server installation, configuration, deployment |
| [`ADMINISTRATION.md`](./ADMINISTRATION.md) | Server administration and moderation |
| [`CLIENT.md`](./CLIENT.md) | Client usage guide |
| [`FAQ.md`](./FAQ.md) | Frequently asked questions |
