# Phase 1: Core Server + E2E DMs

**Duration:** 8-10 weeks
**Goal:** Working single-node server with authenticated users, public text channels, real-time messaging, and E2E encrypted DMs. No private group channels yet — those require MLS in Phase 2.
**Dependencies:** Phase 0 complete (monorepo scaffolded, protocol spec drafted, CI running)
**Deliverable:** A usable chat server with web client. Users can create accounts, join public channels, send messages, and have E2E encrypted DMs.

---

## Review Issues Addressed

- **#2 — Account recovery:** Recovery codes generated at registration
- **#5 — Invite system:** Invite links with codes, expiration, max uses
- **#8 — Monitoring/observability:** Continued from Phase 0 (logging in all new endpoints)
- **#9 — Message formatting:** Server-side sanitization, client-side rendering
- **#11 — WebSocket rate limiting:** Per-connection event rate limiting
- **#12 — Content delivery strategy:** File size limits, thumbnailing, quotas
- **#13 — Redis SPOF:** Graceful degradation for presence/PubSub

---

## Tasks

### Database & Schema

- [ ] **1.1** Ecto schema: `users`
  - `id` (UUID, primary key)
  - `username` (string, unique, validated: alphanumeric + underscore, 3-32 chars)
  - `display_name` (string, optional)
  - `password_hash` (string, Argon2id)
  - `identity_public_key` (binary, Ed25519 — uploaded after registration)
  - `signed_prekey` (binary, X25519)
  - `totp_secret` (encrypted string, nullable)
  - `inserted_at`, `updated_at`

- [ ] **1.2** Ecto schema: `channels`
  - `id` (UUID, primary key)
  - `name` (string, validated: lowercase, hyphens, 2-100 chars)
  - `type` (enum: `public` | `dm`) — **Note: no `private` type until Phase 2**
  - `description` (text, optional)
  - `topic` (string, optional)
  - `inserted_at`, `updated_at`

- [ ] **1.3** Ecto schema: `channel_members`
  - `channel_id` (UUID, FK)
  - `user_id` (UUID, FK)
  - `role` (enum: `owner` | `moderator` | `member`)
  - `joined_at` (datetime)
  - Unique constraint on `{channel_id, user_id}`

- [ ] **1.4** Ecto schema: `messages`
  - `id` (UUID, primary key, UUIDv7 for time-ordering)
  - `channel_id` (UUID, FK, indexed)
  - `author_id` (UUID, FK)
  - `content` (text, nullable — null for encrypted messages)
  - `encrypted_content` (binary, nullable — set for E2E messages)
  - `nonce` (binary, nullable — encryption nonce)
  - `edited_at` (datetime, nullable)
  - `deleted_at` (datetime, nullable — soft delete)
  - `inserted_at` (datetime)
  - Index on `{channel_id, inserted_at}` for pagination

- [ ] **1.5** Ecto schema: `roles`
  - `id` (UUID, primary key)
  - `server_id` (UUID, FK — for future multi-server, scope to default server for now)
  - `name` (string)
  - `permissions` (JSONB map of permission flags)
  - `priority` (integer, higher = more authority)
  - `color` (string, hex color, optional)
  - `inserted_at`, `updated_at`

- [ ] **1.6** Ecto schema: `recovery_codes`
  - `id` (UUID, primary key)
  - `user_id` (UUID, FK)
  - `code_hash` (string, Argon2id hash of recovery code)
  - `used_at` (datetime, nullable)

- [ ] **1.7** Ecto schema: `invite_links`
  - `id` (UUID, primary key)
  - `code` (string, unique, 8-char random alphanumeric)
  - `creator_id` (UUID, FK)
  - `max_uses` (integer, nullable — null = unlimited)
  - `uses` (integer, default 0)
  - `expires_at` (datetime, nullable)
  - `inserted_at`

- [ ] **1.8** Run migrations, write seed script:
  - Default admin user (configurable username/password via env vars)
  - Default `#general` public channel
  - Default `@everyone` role with base permissions

### Authentication

- [ ] **1.9** `POST /api/v1/auth/register`
  - Accept: `username`, `password`
  - Validate: username uniqueness, password strength (min 10 chars, entropy check via `zxcvbn` algorithm or simple rules)
  - Hash password with Argon2id (`comeonin` + `argon2_elixir`)
  - Generate 12 recovery codes (crypto-random, 8-char alphanumeric each)
  - Store hashed recovery codes
  - Return: user object + plaintext recovery codes (shown once, never retrievable again)

- [ ] **1.10** `POST /api/v1/auth/login`
  - Accept: `username`, `password`
  - Verify credentials
  - If 2FA enabled: return `{ "requires_2fa": true, "token": "<partial_token>" }`
  - If no 2FA: return JWT access token (15min expiry) + refresh token (7-day, rotating, stored server-side)

- [ ] **1.11** `POST /api/v1/auth/refresh`
  - Accept: refresh token
  - Validate: not expired, not revoked, matches stored token
  - Rotate: invalidate old refresh token, issue new access + refresh tokens
  - Revocation: store used refresh tokens to prevent replay

- [ ] **1.12** `POST /api/v1/auth/recover`
  - Accept: `username`, `recovery_code`, `new_password`
  - Verify recovery code against stored hashes
  - Mark code as used (one-time use)
  - Reset password, invalidate all sessions

- [ ] **1.13** TOTP 2FA:
  - `POST /api/v1/auth/2fa/enable` — generate TOTP secret, return secret + QR code URI (`nimble_totp`)
  - `POST /api/v1/auth/2fa/verify` — verify TOTP code to confirm setup
  - `POST /api/v1/auth/2fa/disable` — require current TOTP code to disable
  - `POST /api/v1/auth/2fa/authenticate` — verify TOTP during login flow

- [ ] **1.14** WebAuthn/Passkey:
  - `POST /api/v1/auth/webauthn/register` — initiate WebAuthn registration challenge (`wax` library)
  - `POST /api/v1/auth/webauthn/register/complete` — verify attestation, store credential
  - `POST /api/v1/auth/webauthn/authenticate` — initiate authentication challenge
  - `POST /api/v1/auth/webauthn/authenticate/complete` — verify assertion

- [ ] **1.15** Auth plug middleware:
  - `CairnWeb.Plugs.Authenticate` — extract JWT from `Authorization: Bearer <token>`, verify, assign `current_user` to conn
  - WebSocket auth: verify JWT in `connect/3` callback of `UserSocket`
  - Return 401 for invalid/expired tokens with clear error messages

- [ ] **1.16** Password strength validation:
  - Minimum 10 characters
  - Reject passwords found in common breach lists (top 10k, bundled)
  - Reject passwords matching username

### Real-time Messaging

- [ ] **1.17** `UserSocket` module:
  - Authenticate via JWT passed in connection params (`token` key)
  - Reject connections with invalid/expired tokens
  - Assign `user_id` to socket

- [ ] **1.18** `ChannelChannel` (Phoenix Channel):
  - Topic: `channel:<channel_uuid>`
  - `join/3`: verify user is a member of the channel (or channel is public), load recent messages
  - `handle_in("new_msg", ...)`: validate message, persist to DB, broadcast `new_msg` to all channel members
  - `handle_in("typing_start", ...)`: broadcast ephemeral typing event (not persisted)
  - `handle_in("typing_stop", ...)`: broadcast stop typing event

- [ ] **1.19** Message broadcasting flow:
  1. Client sends `new_msg` event with `{ content: "...", nonce: "..." }`
  2. Server validates (non-empty, within length limits, user has `send_messages` permission)
  3. Server persists to PostgreSQL
  4. Server broadcasts `new_msg` event to all subscribers with full message object
  5. Server returns `{:reply, :ok, socket}` with message ID

- [ ] **1.20** `Phoenix.Presence` integration:
  - Track online/offline/idle status per user
  - Presence diff events automatically broadcast to connected clients
  - Idle detection: client sends heartbeat, server marks idle after 5min inactivity
  - **Redis graceful degradation:** if Redis is down, fall back to node-local Phoenix.PubSub (works for single-node, loses cross-node presence in future federation)

- [ ] **1.21** Typing indicators:
  - `typing_start` → broadcast to channel, auto-expire after 8 seconds
  - `typing_stop` → broadcast immediately
  - Client-side: show "User is typing..." for active typers, debounce updates

- [ ] **1.22** Message editing:
  - `handle_in("edit_msg", %{"id" => id, "content" => new_content})`
  - Verify: author matches, message not deleted, within edit window (configurable, default: no limit)
  - Update `content` and `edited_at` timestamp
  - Broadcast `msg_edited` event with message ID + new content

- [ ] **1.23** Message deletion:
  - `handle_in("delete_msg", %{"id" => id})`
  - Verify: author matches OR user has `manage_messages` permission
  - Soft-delete: set `deleted_at`, clear `content` (keep tombstone for sync)
  - Broadcast `msg_deleted` event with message ID

- [ ] **1.24** WebSocket event rate limiting:
  - Per-connection rate limiter: max 10 events/second sustained, burst of 20
  - Typing events: max 1 per 3 seconds
  - Exceeded → warning event to client, then disconnect on repeated violation
  - Implementation: ETS-backed token bucket per socket PID

- [ ] **1.25** Message formatting:
  - Server-side: sanitize Markdown input (strip dangerous patterns, limit nesting depth)
  - Client-side: render Markdown subset (bold, italic, strikethrough, code, links, mentions)
  - Mention resolution: `@username` → user ID lookup, highlighted in client
  - Max message length: 4000 characters

### E2E Encryption (DMs Only)

- [ ] **1.26** Shared crypto library in `proto/` package:
  - Using `sodium-plus` (libsodium.js wrapper)
  - Export: `generateIdentityKeyPair()`, `generatePreKey()`, `generateOneTimePreKeys(count)`, `x3dhInitiate()`, `x3dhRespond()`, `ratchetEncrypt()`, `ratchetDecrypt()`

- [ ] **1.27** Client-side key generation (on first use / account setup):
  - Ed25519 identity key pair (long-term, identifies user)
  - X25519 signed prekey (medium-term, rotated periodically)
  - Batch of 100 one-time X25519 prekeys (consumed per new conversation)

- [ ] **1.28** Private key storage:
  - Web: IndexedDB with encryption (key derived from password via Argon2id)
  - Future: OS keychain (Phase 6 — desktop/mobile)
  - Never transmitted to server in plaintext

- [ ] **1.29** Public key upload:
  - `POST /api/v1/users/me/keys` — upload identity public key, signed prekey (with signature), one-time prekeys
  - `PUT /api/v1/users/me/keys/prekey` — rotate signed prekey
  - `POST /api/v1/users/me/keys/one-time` — upload additional one-time prekeys when running low

- [ ] **1.30** Key bundle retrieval:
  - `GET /api/v1/users/:id/keys` — returns:
    - Identity public key
    - Signed prekey + signature
    - One one-time prekey (consumed — removed from server after retrieval)
  - If no one-time prekeys remain, return bundle without (X3DH still works, slightly weaker)

- [ ] **1.31** X3DH key agreement (client-side, in `proto/`):
  - Initiator: fetch recipient's key bundle, perform X3DH, derive shared secret
  - Responder: receive initial message with ephemeral key, perform X3DH, derive same shared secret
  - Output: shared secret → initialize Double Ratchet

- [ ] **1.32** Double Ratchet (client-side, in `proto/`):
  - Symmetric ratchet: KDF chain for message keys (forward secrecy per message)
  - DH ratchet: new DH exchange periodically (every N messages or on reply)
  - Message format: `{ header: { dh_public, prev_chain_length, message_number }, ciphertext, nonce }`
  - Out-of-order handling: store skipped message keys (bounded buffer, max 1000)

- [ ] **1.33** DM message flow:
  1. Initiator opens DM → fetch recipient key bundle → X3DH → init ratchet
  2. Encrypt message with current ratchet key → send via WebSocket as `encrypted_content` + `nonce`
  3. Server persists `encrypted_content` + `nonce` (cannot read content)
  4. Recipient receives → decrypt with ratchet → display plaintext
  5. Ratchet advances after each message

- [ ] **1.34** Crypto test suite (`proto/tests/crypto/`):
  - Key generation produces valid key pairs
  - X3DH: two parties derive same shared secret
  - Double Ratchet: encrypt/decrypt round-trip
  - Forward secrecy: old keys cannot decrypt new messages
  - Out-of-order messages: messages delivered out of order are decrypted correctly
  - Session recovery: ratchet state can be serialized/deserialized
  - Fuzz testing: random message ordering, dropped messages

### Storage

- [ ] **1.35** `StorageBackend` Elixir behaviour:
  ```elixir
  @callback put(binary(), binary()) :: {:ok, String.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, :not_found}
  @callback delete(String.t()) :: :ok | {:error, term()}
  @callback exists?(String.t()) :: boolean()
  ```

- [ ] **1.36** `LocalFileBackend`:
  - Store files by SHA-256 content hash (content-addressable, deduplication)
  - Directory structure: `uploads/<first-2-hash-chars>/<full-hash>`
  - Metadata in PostgreSQL: `files` table (id, hash, filename, content_type, size, uploader_id, inserted_at)

- [ ] **1.37** `S3CompatibleBackend`:
  - Via `ex_aws` + `ex_aws_s3`
  - Configurable: endpoint, bucket, access key, secret key
  - Same content-hash keying as local backend

- [ ] **1.38** Runtime storage config:
  - `STORAGE_BACKEND=local|s3` environment variable
  - `STORAGE_PATH` for local backend
  - `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` for S3

- [ ] **1.39** Upload endpoint:
  - `POST /api/v1/upload` — multipart form data
  - Hash content (SHA-256), check for duplicate, store via backend
  - Return: `{ "id": "<file_id>", "url": "/api/v1/files/<file_id>", "hash": "<sha256>" }`
  - `GET /api/v1/files/:id` — serve file with proper `Content-Type` and caching headers

- [ ] **1.40** Client-side file encryption for DM attachments:
  - Generate random AES-256-GCM key
  - Encrypt file before upload
  - Upload encrypted blob
  - Send file key + file ID in the DM message (encrypted by Double Ratchet)
  - Recipient: download blob → decrypt with file key → display

- [ ] **1.41** File restrictions:
  - Max file size: 25MB (configurable via `MAX_FILE_SIZE` env var)
  - Content type allowlist: images (jpg, png, gif, webp), video (mp4, webm), audio (mp3, ogg, wav), documents (pdf, txt)
  - Per-user upload quota: 500MB (configurable, tracked in user record)

- [ ] **1.42** Image thumbnailing:
  - Generate thumbnails for image uploads (max 400x400, JPEG quality 80)
  - Implementation: `image` Elixir library (NIF-based) or shell out to `vips`/`sharp`
  - Store thumbnail alongside original, serve via `GET /api/v1/files/:id/thumbnail`

### Web Client

- [ ] **1.43** Project setup:
  - React 18+ with Vite + TypeScript (strict mode)
  - Dependencies: `zustand` (state), `phoenix` (WebSocket), `sodium-plus`, `react-router-dom`
  - Project structure: `src/` with `components/`, `stores/`, `hooks/`, `lib/` (crypto, api), `pages/`

- [ ] **1.44** Auth flow UI:
  - Registration page: username + password + confirm password
  - Post-registration: modal showing 12 recovery codes with "I've saved these" confirmation
  - Login page: username + password
  - 2FA prompt: TOTP code input (shown when server returns `requires_2fa`)
  - Token storage: access token in memory (zustand), refresh token in httpOnly cookie or secure storage

- [ ] **1.45** Main layout:
  - Left sidebar: channel list (public channels), DM list, user info at bottom
  - Center: message area with input at bottom
  - Right panel (collapsible): member list with presence indicators
  - Responsive: sidebar collapses on narrow viewports

- [ ] **1.46** Real-time messaging:
  - Connect to Phoenix WebSocket via `phoenix` npm package
  - Join channel on selection → receive message history (last 50)
  - Send message: input → WebSocket `new_msg` event
  - Receive message: `new_msg` event → append to message list
  - Scroll behavior: auto-scroll to bottom on new messages (unless user scrolled up)
  - Infinite scroll up for message history (cursor-based pagination)

- [ ] **1.47** Presence:
  - Online/offline dots next to usernames (green/gray)
  - Typing indicators: "Alice is typing..." or "Alice and Bob are typing..." or "Several people are typing..."
  - Member list sorted: online first, then alphabetical

- [ ] **1.48** E2E encryption DM flow:
  - First DM: prompt user to generate keys (if not already done)
  - Opening DM: perform X3DH handshake (transparent to user)
  - Lock icon on encrypted conversations
  - Message input: encrypt before send, decrypt on receive
  - Loading state while decrypting history on DM open

- [ ] **1.49** File upload UI:
  - Drag-and-drop onto message area, or click attachment button
  - Progress indicator during upload
  - Preview: images shown inline, other files as download links
  - DM files: "Encrypting..." indicator during client-side encryption

- [ ] **1.50** Invite links:
  - Settings panel: generate invite link (with optional max uses, expiration)
  - Copy to clipboard button
  - Join via invite: `/invite/<code>` route → verify code → join server
  - `POST /api/v1/invites` — create invite
  - `POST /api/v1/invites/:code/accept` — use invite to join
  - `GET /api/v1/invites/:code` — get invite info (valid, uses remaining, etc.)

- [ ] **1.51** Safety number verification:
  - Settings → DM conversation → "Verify encryption"
  - Display safety number (hash of both users' identity keys)
  - Compare out-of-band (show as numeric code + QR code)

---

## Testing Checkpoint

- [ ] Register 2 users, verify recovery codes are displayed and stored (hashed)
- [ ] Create public channel, send messages, verify real-time delivery
- [ ] Edit and delete messages, verify propagation
- [ ] Initiate DM between 2 users, verify E2E encryption:
  - Server database contains only `encrypted_content` (no plaintext)
  - Both users can read messages
  - Key rotation occurs (Double Ratchet advances)
- [ ] Upload file in DM, verify server stores only encrypted blob
- [ ] Test account recovery: use recovery code to reset password
- [ ] Generate invite link, use it to join from a new account
- [ ] Test 2FA: enable TOTP, verify login requires code
- [ ] Verify WebSocket rate limiting: rapid-fire events get throttled
- [ ] Load test: 100 concurrent WebSocket connections, message throughput
- [ ] Verify `/health` endpoint reports all services status

---

## Notes

- The `dm` channel type is limited to exactly 2 members. The server enforces this.
- There is deliberately no `private` channel type in this phase. That is Phase 2.
- Recovery codes are a stopgap. Full encrypted key backup comes in Phase 2.
- The web client is the primary client for all phases until Phase 6. Desktop and mobile share the same proto/ library.
- **Web client serving model:** Phoenix serves the web client as static assets from `priv/static/`. During development, Vite runs as a dev server with proxy to Phoenix. For production builds, the web client is compiled and copied into the Phoenix release. There is no separate web deployment — the server *is* the web host. Set this up early so the dev workflow is smooth from day one.
