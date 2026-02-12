# Phase 3.5: Federation

**Status:** Complete
**Goal:** Implement node-to-node federation so that multiple Cairn instances can discover each other, verify identity, and exchange messages with causal ordering and privacy protections.
**Dependencies:** Phase 3 complete (Server/Guild entity, per-server roles, permissions, 137 server tests).
**Deliverable:** Two or more Cairn nodes can federate — ActivityPub inbox/outbox, HTTP message signatures (RFC 9421), HLC timestamps, Follow/Accept handshake, message/edit/delete federation, metadata stripping, per-node rate limiting.

---

## Architecture Overview

Federation uses ActivityPub as the message transport with Cairn-specific extensions. Each node has an Ed25519 identity key for signing, discovered via well-known endpoints. Messages are delivered asynchronously via Oban job queues with exponential backoff. Hybrid Logical Clocks provide causal ordering across nodes.

```
Node A                                          Node B
  │                                                │
  ├─ GET /.well-known/cairn-federation ───────►│
  │◄──────────────────── {node_id, public_key} ────┤
  │                                                │
  ├─ POST /inbox  (Follow activity, signed) ──────►│
  │◄──────────────────── POST /inbox (Accept) ─────┤
  │                                                │
  ├─ POST /inbox  (Create message, signed) ───────►│
  │   [Oban worker, exponential backoff]           │
  │   [HTTP Signature + Content-Digest]            │
  │   [Metadata stripped, HLC timestamp]           │
```

---

## Node Identity

### `Cairn.Federation.NodeIdentity` (GenServer)

Generates and persists an Ed25519 signing key pair on first boot.

- **Storage:** Binary file at configurable path (`NODE_KEY_PATH`, default: `priv/keys/node_ed25519.key`), 0600 permissions
- **Serialization:** `:erlang.term_to_binary` / `binary_to_term` with `try/rescue ArgumentError` for corrupted files
- **API:**
  - `public_key/0` — raw 32-byte public key
  - `public_key_base64/0` — Base64-encoded public key
  - `node_id/0` — SHA-256 fingerprint of public key (hex-encoded)
  - `sign/1` — Ed25519 signature over arbitrary binary
  - `verify/3` — stateless signature verification (message, signature, public_key)
- **Config:** `FEDERATION_ENABLED=true` + `CAIRN_DOMAIN` env vars required
- **Supervision:** Conditional child of Application supervisor, only started when federation enabled
- **Global name:** `__MODULE__` — tests must be `async: false` or carefully stop/start

---

## Well-Known Endpoints

### `CairnWeb.FederationController`

Three unauthenticated endpoints for node discovery:

| Method | Path | Description |
|---|---|---|
| GET | `/.well-known/cairn-federation` | Node identity, public key, inbox URL, capabilities |
| GET | `/.well-known/privacy-manifest` | Privacy practices, retention, federation policies |
| GET | `/.well-known/webfinger?resource=acct:user@domain` | RFC 7033 user discovery, returns JRD with AP actor URI |

**Federation metadata response:**
```json
{
  "protocol": "cairn",
  "version": "1.0.0",
  "nodeName": "My Node",
  "domain": "example.com",
  "inbox": "https://example.com/inbox",
  "outbox": "https://example.com/outbox",
  "publicKey": {
    "id": "https://example.com/federation#main-key",
    "type": "Ed25519",
    "publicKeyPem": "<base64>"
  },
  "capabilities": ["messaging", "channels", "mls"]
}
```

**WebFinger:** Resolves `acct:username@domain` to AP actor URI. Returns 404 for unknown users. Only resolves users when queried domain matches `CAIRN_DOMAIN`.

---

## Federation Data Model

### Migration: `20260210200443_create_federation_tables.exs`

Two tables:

- **`federated_nodes`**: `domain` (unique), `node_id`, `public_key`, `inbox_url`, `protocol_version`, `privacy_manifest` (JSONB), `status` (pending/active/blocked), timestamps
- **`federation_activities`**: `federated_node_id` (FK), `activity_type`, `direction` (inbound/outbound), `actor_uri`, `object_uri`, `payload` (JSONB), `status` (pending/delivered/failed), `error`, timestamps

### `Cairn.Federation` (context)

- `register_node/1`, `get_node/1`, `get_node_by_domain/1`, `list_nodes/0`
- `block_node/1`, `unblock_node/1`, `update_node_status/2`
- `log_activity/1`, `list_activities/1` (with filtering)
- `active_nodes/0` — only nodes with status "active"

### Admin API

Pipeline: `[:api, :authenticated, :admin]` with `AdminAuth` plug (checks if user is server creator or configured `admin_user_id`).

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/admin/federation/nodes` | List all federated nodes |
| POST | `/api/v1/admin/federation/nodes` | Register new node |
| GET | `/api/v1/admin/federation/nodes/:id` | Show node details |
| POST | `/api/v1/admin/federation/nodes/:id/block` | Block a node |
| POST | `/api/v1/admin/federation/nodes/:id/unblock` | Unblock a node |
| GET | `/api/v1/admin/federation/activities` | List federation activity log |

---

## HTTP Message Signatures (RFC 9421)

### `Cairn.Federation.HttpSignatures`

Signs outbound requests and verifies inbound requests per RFC 9421.

**Covered components:** `@method`, `@target-uri`, `@authority`, `content-type`, `content-digest`, `date`

- `sign_request/5` — takes method, URL, headers, body, sign_fn → returns headers map with `signature`, `signature-input`, `content-digest`, `date`
- `verify_request/2` — takes params map (method, url, headers, body) and public_key → returns `:ok` or `{:error, atom()}`
- **Date validation:** Rejects requests with `date` header older than 300 seconds
- **Signature format:** `sig1=:base64:` with `sig1=(...components...);keyid="node-key";alg="ed25519";created=<unix>`

### `Cairn.Federation.ContentDigest` (RFC 9530)

- `generate/1` — SHA-256 digest of request body, formatted as `sha-256=:base64:`
- `verify/2` — verifies Content-Digest header matches body

### `CairnWeb.Plugs.VerifyHttpSignature`

Plug applied to `/inbox` route. Extracts signature from headers, fetches signer's public key from `FederatedNode` record, verifies signature. Returns 401 on failure.

---

## ActivityPub

### `Cairn.Federation.ActivityPub` (serializers)

Converts internal Ecto schemas to AP JSON-LD format:

- `serialize_user/1` → AP Person with public key
- `serialize_server/1` → AP Group (CairnServer extension)
- `serialize_channel/1` → AP Collection (CairnChannel extension)
- `serialize_message/1` → AP Note (CairnMessage extension) with HLC timestamp
- `wrap_activity/3` → wraps object in Create/Update/Delete activity envelope

All activities include `@context` with ActivityStreams and Cairn namespace.

### `Cairn.Federation.InboxHandler`

Dispatches inbound activities by type:

| Activity Type | Handler | Description |
|---|---|---|
| `Follow` | `handle_follow/2` | Channel subscription request → auto-Accept for public channels |
| `Accept` | `handle_accept/2` | Confirms Follow was accepted, activates subscription |
| `Create` | `handle_create/2` | New message → persist locally, broadcast to channel subscribers |
| `Update` | `handle_update/2` | Message edit → update local message |
| `Delete` | `handle_delete/2` | Message deletion → soft-delete local message |

### `CairnWeb.InboxController`

- `POST /inbox` — receives AP activities, protected by `VerifyHttpSignature` and `FederationRateLimiter` plugs
- Logs all inbound activities via `Federation.log_activity/1`

### `CairnWeb.ActorController`

- `GET /users/:username` — AP Person document with public key
- `GET /users/:username/outbox` — AP OrderedCollection of user's public activities

---

## Oban Delivery

### Migration: `20260210203241_add_oban_jobs_table.exs`

Oban jobs table (version 12).

### Config

```elixir
# config.exs
config :cairn, Oban, repo: Cairn.Repo, queues: [default: 10, federation: 10]

# test.exs
config :cairn, Oban, testing: :inline  # runs jobs synchronously in tests
```

### `Cairn.Federation.DeliveryWorker` (Oban.Worker)

- Queue: `:federation`, max_attempts: 15
- `perform/1` — strips metadata, signs request with HTTP Signatures, POSTs to remote inbox via `Req`
- `backoff/1` — exponential: `2^attempt` minutes, capped at 72 hours
- `enqueue/3` — creates Oban job with `inbox_url`, `activity`, `federated_node_id`
- Logs success/failure via `Federation.log_activity/1`

---

## Hybrid Logical Clock (HLC)

### Migration: `20260210203744_add_hlc_to_messages.exs`

Added to messages table: `hlc_wall` (bigint), `hlc_counter` (integer, default 0), `hlc_node` (string)

### `Cairn.Federation.HLC` (GenServer)

Provides monotonic timestamps for causal ordering across nodes.

- `now/1` — returns `{wall_ms, counter, node_id}`, advances clock
- `update/4` — merges with remote timestamp: `max(local_wall, remote_wall)`, increments counter
- `compare/2` — compares two HLC timestamps for ordering
- **Drift protection:** Rejects remote timestamps more than 60 seconds in the future
- **Storage:** GenServer state with named process (conditional start when federation enabled)

### Message Schema Update

`Cairn.Chat.Message` — added `hlc_wall`, `hlc_counter`, `hlc_node` fields.

---

## Federation Handshake

### `Cairn.Federation.Handshake`

Implements the Follow/Accept protocol for establishing federation:

1. `initiate/1` — fetches remote `/.well-known/cairn-federation`, validates response, registers node, sends Follow activity via DeliveryWorker
2. `handle_follow/2` — receives Follow from remote node, auto-accepts for public channels, sends Accept back
3. `handle_accept/2` — confirms handshake, updates node status to "active"

---

## Message Federation

### `Cairn.Federation.MessageFederator`

Bridges local message events to federation delivery:

- `federate_create/2` — on local message create, wraps in Create activity, enqueues delivery to all active nodes
- `federate_update/2` — on message edit, sends Update activity
- `federate_delete/2` — on message delete, sends Delete activity

Called from `ChannelChannel` after message creation/edit/deletion.

---

## Safety Controls

### Metadata Stripping

#### `Cairn.Federation.MetadataStripper`

Strips sensitive metadata from all outbound activities before federation:

**Stripped keys:** `ip`, `user_agent`, `device_id`, `device_fingerprint`, `session_id`, `request_id`, `client_version`, `internal_id`, `database_id`

- Operates recursively on nested maps and lists
- Applied in `DeliveryWorker` before signing and sending

### Rate Limiting

#### `Cairn.Federation.FederationRateLimiter`

Per-node Redis-backed rate limiting:

- Default: 100 requests/minute, burst up to 200
- Uses Redis INCR with 60-second TTL window
- `check/1` — returns `:ok` or `{:error, :rate_limited}`
- `current_count/1` — returns current request count for a domain
- Graceful degradation: allows through if Redis is unavailable

#### `CairnWeb.Plugs.FederationRateLimiter`

Plug applied to `/inbox` route. Extracts domain from request, checks rate limit, returns 429 Too Many Requests when exceeded.

### Defederation

Admin API supports blocking nodes:
- `POST /api/v1/admin/federation/nodes/:id/block` — sets status to "blocked"
- Blocked nodes: rejected at inbox (signature verification fails for unknown/blocked nodes), excluded from `active_nodes/0` query (no outbound delivery)
- Unblock resumes federation

---

## Proto Types Added

```typescript
interface FederatedNode {
  id: string;
  domain: string;
  node_id: string;
  status: "pending" | "active" | "blocked";
  protocol_version: string;
  inserted_at: string;
}

interface FederationActivity {
  id: string;
  activity_type: string;
  direction: "inbound" | "outbound";
  actor_uri?: string;
  object_uri?: string;
  status: "pending" | "delivered" | "failed";
  error?: string;
  node_domain: string;
  inserted_at: string;
}
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `FEDERATION_ENABLED` | `false` | Enable federation features |
| `CAIRN_DOMAIN` | — | This node's public domain |
| `NODE_KEY_PATH` | `priv/keys/node_ed25519.key` | Path to Ed25519 key file |

### Application Config

```elixir
# Federation defaults
config :cairn, :federation,
  enabled: false,
  domain: nil,
  rate_limit: 100,
  rate_burst: 200

# Oban job queues
config :cairn, Oban,
  repo: Cairn.Repo,
  queues: [default: 10, federation: 10]
```

---

## Test Coverage

| Test File | Tests | Description |
|---|---|---|
| `federation/node_identity_test.exs` | 9 | Key generation, persistence, signing, verification |
| `controllers/federation_controller_test.exs` | 10 | Well-known endpoints, WebFinger |
| `federation_test.exs` | 9 | Node CRUD, activity logging, status management |
| `federation/http_signatures_test.exs` | 11 | Sign/verify roundtrip, tampered/expired rejection |
| `federation/activity_pub_test.exs` | 4 | AP serializers for user, server, channel, message |
| `federation/inbox_handler_test.exs` | 5 | Activity dispatch (Follow, Accept, Create, Update, Delete) |
| `federation/hlc_test.exs` | 9 | Clock monotonicity, merge, drift protection |
| `federation/handshake_test.exs` | 2 | Follow/Accept protocol |
| `federation/message_federator_test.exs` | 4 | Create/Update/Delete federation |
| `federation/metadata_stripper_test.exs` | 4 | Recursive stripping of sensitive keys |
| `federation/rate_limiter_test.exs` | 4 | Redis rate limiting, burst, rejection |

**Final count after Phase 3.5:** 208 server tests, 0 failures.

---

## Files Created

### Server — Modules

| File | Description |
|---|---|
| `lib/cairn/federation/node_identity.ex` | GenServer for Ed25519 key management |
| `lib/cairn/federation/federated_node.ex` | FederatedNode Ecto schema |
| `lib/cairn/federation/federation_activity.ex` | FederationActivity Ecto schema |
| `lib/cairn/federation.ex` | Federation context (node CRUD, activity logging) |
| `lib/cairn/federation/content_digest.ex` | RFC 9530 Content-Digest |
| `lib/cairn/federation/http_signatures.ex` | RFC 9421 HTTP Message Signatures |
| `lib/cairn/federation/activity_pub.ex` | AP serializers |
| `lib/cairn/federation/inbox_handler.ex` | Inbound activity dispatcher |
| `lib/cairn/federation/delivery_worker.ex` | Oban outbound delivery worker |
| `lib/cairn/federation/hlc.ex` | Hybrid Logical Clock GenServer |
| `lib/cairn/federation/handshake.ex` | Follow/Accept handshake protocol |
| `lib/cairn/federation/message_federator.ex` | Message → federation bridge |
| `lib/cairn/federation/metadata_stripper.ex` | Outbound metadata stripping |
| `lib/cairn/federation/federation_rate_limiter.ex` | Redis per-node rate limiting |

### Server — Controllers & Plugs

| File | Description |
|---|---|
| `lib/cairn_web/controllers/federation_controller.ex` | Well-known endpoints |
| `lib/cairn_web/controllers/inbox_controller.ex` | AP inbox (POST /inbox) |
| `lib/cairn_web/controllers/actor_controller.ex` | AP actor profiles |
| `lib/cairn_web/controllers/admin/federation_controller.ex` | Admin federation CRUD |
| `lib/cairn_web/plugs/admin_auth.ex` | Admin authorization |
| `lib/cairn_web/plugs/verify_http_signature.ex` | Inbound signature verification |
| `lib/cairn_web/plugs/federation_rate_limiter.ex` | Per-node rate limiting plug |

### Server — Migrations

| File | Description |
|---|---|
| `priv/repo/migrations/20260210200443_create_federation_tables.exs` | federated_nodes + federation_activities |
| `priv/repo/migrations/20260210203241_add_oban_jobs_table.exs` | Oban jobs table |
| `priv/repo/migrations/20260210203744_add_hlc_to_messages.exs` | HLC fields on messages |

### Server — Modified Files

| File | Change |
|---|---|
| `mix.exs` | Added `{:oban, "~> 2.18"}` |
| `config/config.exs` | Federation config, Oban config |
| `config/test.exs` | Oban inline testing mode |
| `config/runtime.exs` | FEDERATION_ENABLED, CAIRN_DOMAIN, NODE_KEY_PATH |
| `lib/cairn/application.ex` | Oban child, conditional federation children |
| `lib/cairn/chat/message.ex` | HLC fields |
| `lib/cairn_web/router.ex` | Federation routes, admin routes, well-known, inbox/outbox, actor |
| `lib/cairn_web/channels/channel_channel.ex` | MessageFederator calls on create/edit/delete |

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Node key storage | File-based, configurable path | Survives DB reset, operator can back up |
| HTTP Signatures | Custom RFC 9421 via `:crypto` | No mature Elixir library for RFC 9421; ~100 lines |
| Delivery queue | Oban (`{:oban, "~> 2.18"}`) | Standard Elixir job queue with retries, backoff |
| HLC implementation | GenServer + state | Monotonic local state, drift protection |
| Activity storage | JSONB in federation_activities | Audit trail, replay, debugging |
| Test mode | Oban `testing: :inline` | Jobs run synchronously in tests |
| Signature algorithm | Ed25519 | Fast, small signatures, used by protocol spec |
| Rate limiting backend | Redis (INCR + EXPIRE) | Distributed, same Redis instance as presence |

---

## Notable Implementation Details

- **NodeIdentity global name:** Tests that use NodeIdentity must be `async: false` or carefully manage start/stop to avoid name conflicts
- **Oban inline mode:** Jobs execute synchronously in tests, which means `DeliveryWorker.enqueue` immediately calls `NodeIdentity.sign` — tests must start NodeIdentity in setup
- **`register_user` return format:** Returns `{:ok, {user, recovery_codes}}` (tuple inside ok), not `{:ok, user, codes}`
- **Content-Digest:** SHA-256 per RFC 9530, required for body integrity in signed requests
- **Metadata stripping:** Recursive — handles nested maps and lists within AP activities
- **Rate limiter graceful degradation:** If Redis is unavailable, requests are allowed through (fail-open for availability)
