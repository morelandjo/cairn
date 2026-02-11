# Murmuring Threat Model

## Overview

Murmuring is a privacy-first federated communication platform. This document identifies trust boundaries, attack surfaces, threat actors, and mitigations.

## Trust Boundaries

### Client ↔ Server
- **Transport:** TLS 1.3 required. All HTTP and WebSocket connections are encrypted in transit.
- **Trust model:** The server is trusted for metadata (who sent a message, when, to which channel) but **not** for message content. E2EE (MLS + Double Ratchet) ensures only recipients can read message bodies.
- **Authentication:** JWT access tokens (15-minute expiry) + refresh tokens. TOTP and WebAuthn 2FA supported.

### Server ↔ SFU
- **Transport:** Internal network, authenticated via shared secret Bearer token.
- **Trust model:** SFU is a trusted component operated by the same party as the server. It handles media routing but voice frames are E2E encrypted via Insertable Streams (AES-128-GCM from MLS epoch secrets).

### Server ↔ Federation Peers
- **Transport:** HTTPS with HTTP Signatures (RFC 9421) for request authentication.
- **Trust model:** Remote nodes are **partially trusted**. Each node's identity is verified via Ed25519 keys published at `/.well-known/murmuring-federation`. Federated messages have metadata stripped before relay. Remote nodes can be blocked (defederated) by operators.
- **User identity:** Remote users authenticate via federated auth tokens signed by their home node. User identity is verified via `did:murmuring` operation chains — self-certifying, tamper-evident, and independently verifiable by any node.

### Server ↔ Database
- **Transport:** TLS optional (recommended for remote databases). Connection via Ecto/Postgrex.
- **Trust model:** Database is trusted infrastructure. Operator-managed.

### Server ↔ Redis
- **Transport:** Local connection, optionally TLS.
- **Trust model:** Trusted for transient state (presence, pubsub). No secrets stored.

### Server ↔ Meilisearch
- **Transport:** Local HTTP, optionally with API key.
- **Trust model:** Trusted for search indexing. Only indexes message metadata and content for searchable channels.

## Attack Surfaces

### Authentication Endpoints
- **Surface:** `POST /api/v1/auth/register`, `/auth/login`, `/auth/refresh`, `/auth/recover`
- **Threats:** Credential stuffing, brute force, account enumeration, token theft, automated registration spam
- **Mitigations:**
  - Argon2id password hashing (memory-hard, timing-safe)
  - Rate limiting: 5 login attempts/min/IP, 3 registrations/hour/IP
  - ALTCHA proof-of-work on registration: client must solve a SHA-256 challenge (~1-2s of computation), making bulk account creation computationally expensive. Challenge issued via `GET /api/v1/auth/challenge`, solution submitted with registration payload. HMAC-signed to prevent forgery. Privacy-preserving — no third-party calls or user tracking.
  - Honeypot field: hidden `website` field in registration form; bots that auto-fill it are rejected. Invisible to real users.
  - Constant-time error responses (no enumeration)
  - Refresh token rotation on each use
  - TOTP/WebAuthn 2FA

### WebSocket Connections
- **Surface:** Phoenix channels for real-time messaging, presence, voice signaling
- **Threats:** Message flooding, connection exhaustion, unauthorized channel access
- **Mitigations:**
  - JWT auth required for socket connection
  - Per-action rate limiting (10 msg/s, 1 typing/3s, 5 speaking/s)
  - Channel authorization checks on join
  - Connection limits per user

### Federation Inbox
- **Surface:** `POST /inbox` — receives ActivityPub activities from remote nodes
- **Threats:** Replay attacks, message forgery, DDoS from malicious nodes, metadata leakage, user impersonation
- **Mitigations:**
  - HTTP Signature verification (Ed25519, RFC 9421)
  - Per-node rate limiting (100 req/min/node)
  - Node blocklist (defederation)
  - HLC timestamps prevent replay
  - Metadata stripping on relay
  - DID operation chain verification prevents user impersonation (cryptographic proof of identity)
  - Author resolution by DID (preferred) or actor URI (fallback) with verification

### Federated Authentication
- **Surface:** `POST /api/v1/federated/*` — remote users joining servers, listing channels
- **Threats:** Token forgery, replay attacks, unauthorized access, impersonation
- **Mitigations:**
  - Federated auth tokens signed by home node's Ed25519 key (verified against `federated_nodes`)
  - Token expiration (1 hour) + issued-at freshness check (300s skew)
  - Target instance field prevents cross-instance replay
  - DID operation chain verification ensures token holder matches claimed identity
  - Nonce field prevents token reuse

### File Upload
- **Surface:** `POST /api/v1/upload`
- **Threats:** Malicious file upload, path traversal, storage exhaustion, SSRF via link previews
- **Mitigations:**
  - File type validation (allowlist)
  - Size limits (configurable, default 10MB)
  - Rate limiting (10 uploads/min/user)
  - Randomized storage paths (UUID-based)
  - SSRF-safe link preview fetcher (private IP blocking, DNS rebind protection)
  - Image processing via libvips (memory-safe)

### Voice Signaling
- **Surface:** Phoenix VoiceChannel, TURN credential endpoint
- **Threats:** Unauthorized voice access, TURN abuse, media injection
- **Mitigations:**
  - Channel permission checks for voice join
  - HMAC-SHA1 short-lived TURN credentials (12h TTL)
  - Capacity enforcement (max participants per room)
  - E2E voice encryption (Insertable Streams, AES-128-GCM)

### Cross-Instance DM
- **Surface:** `POST /api/v1/dm/federated`, DM hint delivery via federation inbox, `POST /api/v1/dm/requests/:id/respond`
- **Threats:** DM request spam/flooding, unwanted contact, sender impersonation, DM hint forgery, metadata leakage (recipient's home instance learns sender DID + channel ID)
- **Mitigations:**
  - Consent-first: recipient must explicitly accept before messages flow
  - Rate limiting: max 10 DM requests/hour per user, max 5 pending per recipient
  - DID-based block list: blocked DIDs cannot send new requests
  - DM hints authenticated via HTTP Signatures (node-to-node)
  - Sender identity verified via `did:murmuring` — no impersonation possible without rotation key
  - DM messages never federated via ActivityPub — only the hint crosses instances
  - DM channel hosted on one instance only — no cross-instance message replication
  - E2EE (X3DH + Double Ratchet) — hosting instance only sees ciphertext
  - Duplicate request prevention (unique constraint on sender + recipient DID)

### Admin Endpoints
- **Surface:** `/api/v1/admin/*` — federation management, operator tools
- **Threats:** Privilege escalation, unauthorized access
- **Mitigations:**
  - Admin auth plug (separate from user auth)
  - Audit logging for all admin actions
  - IP allowlist (configurable)

## Threat Actors

### Malicious Users
- **Goal:** Spam, harassment, data exfiltration, account takeover
- **Capabilities:** Valid account, client-side tools
- **Mitigations:** Rate limiting, moderation tools (mute/ban/kick), auto-mod rules, reporting system, slow mode

### Compromised Federation Nodes
- **Goal:** Inject malicious content, harvest metadata, impersonate users
- **Capabilities:** Valid federation credentials, control over their own node
- **Mitigations:** HTTP signature verification, metadata stripping, defederation capability, audit logging of federation activity, DID operation chain verification (a compromised node cannot forge another node's users' DIDs without possessing their rotation keys)

### Network Attackers (MITM)
- **Goal:** Eavesdrop on communications, intercept credentials
- **Capabilities:** Network position between client and server
- **Mitigations:** TLS everywhere, HSTS headers, E2EE for message content, E2E voice encryption

### Compromised Server Operator
- **Goal:** Read private communications, manipulate user data
- **Capabilities:** Full database access, server-side code modification
- **Mitigations:** E2EE ensures message content is opaque to the server. Key backup is client-encrypted. Voice frames are E2E encrypted. Server can only access metadata.

### Automated Attacks (Bots/Scripts)
- **Goal:** Account creation spam, credential stuffing, API abuse
- **Capabilities:** Automated HTTP requests at scale
- **Mitigations:** Rate limiting at all endpoints, registration limits, ALTCHA proof-of-work challenge, honeypot field, IP-based throttling

## Assumptions

1. **Server operator is trusted for metadata** — they can see who communicates with whom, when, and in which channels. They cannot read E2EE message content.
2. **Client devices are trusted** — if a device is compromised, the attacker has access to decrypted messages. Device-level security (biometric lock, secure storage) mitigates this.
3. **TLS certificate authorities are trusted** — standard web PKI assumptions apply.
4. **MLS protocol is sound** — we rely on the security guarantees of the MLS protocol for group E2EE.
5. **Federation peers act in good faith by default** — malicious peers can be defederated once detected.

## Data Classification

| Data Type | Sensitivity | Encryption | Retention |
|-----------|------------|------------|-----------|
| Message content | High | E2EE (MLS/Double Ratchet) | User-controlled |
| User credentials | Critical | Argon2id hash | Permanent |
| Session tokens | High | Signed JWT | 15min access, 30d refresh |
| Federation keys | Critical | Ed25519 | Rotatable (7-day grace) |
| DID operation chain | Critical | Signed (Ed25519 rotation key) | Permanent (identity history) |
| Rotation keys | Critical | Encrypted key backup (Argon2id KDF) | Permanent (recovery via codes) |
| Federated auth tokens | High | Node Ed25519 signature | 1 hour expiry |
| Federated user cache | Low | TLS in transit | Refreshed on activity |
| Metadata (timestamps, channels) | Medium | TLS in transit | Configurable |
| Audit logs | Medium | At rest (optional) | 90 days default |
| File uploads | Variable | TLS in transit, at rest (optional) | User-controlled |
| Voice frames | High | E2E (AES-128-GCM) | Not stored |
| DM requests/hints | Medium | TLS in transit, HTTP Signatures | Until accepted/rejected |
| DM block list | Low | TLS in transit | User-controlled |
