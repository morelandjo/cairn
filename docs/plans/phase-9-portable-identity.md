# Phase 9: Portable Cryptographic Identity

**Status:** Complete
**Goal:** Enable portable user identity across federated instances using self-certifying `did:cairn` identifiers with hash-chained operation logs, so users can join servers on any federated instance without re-registering.
**Dependencies:** Phase 3.5 complete (federation infrastructure), Phase 8 complete (hardening/deployment).
**Deliverable:** Users register once on their home instance and join servers on remote instances via federated auth tokens. DIDs are stable across key rotations, independently verifiable, and support key compromise recovery.

---

## Architecture Summary

- **Identity** = `did:cairn:<base58(SHA-256(genesis_op))>` -- stable, never changes
- **Two key pairs**: signing key (daily use) + rotation key (identity operations only)
- **Operation log** = hash-chained, signed operations (create, rotate_signing_key, rotate_rotation_key, update_handle, deactivate). Self-verifying, tamper-evident.
- **Home instance** = where you register, authenticate, store DMs/settings, host operation log
- **Remote servers** = join via federated auth token (no re-registration)
- **Client** = maintains WebSocket per connected instance
- **DMs** = never federated, always on home instance
- **Key compromise recovery** = rotation key can revoke compromised signing key. Recovery codes can rotate the rotation key itself.
- **Impersonation** = impossible (DID is cryptographic, operation chain is verifiable)

---

## Implementation Summary

### Batch 1: DID Foundation

- `did:cairn` specification with two key pairs (signing + rotation)
- `did_operations` table with hash-chained, signed operation log
- `Cairn.Identity` context: `create_did/3`, `rotate_signing_key/3`, `resolve_did/1`, `verify_operation_chain/1`
- DID document serving at `GET /.well-known/did/:did`
- WebFinger resolution for `did:cairn:...` resources
- DID claim in JWT tokens, DID in auth responses
- `alsoKnownAs: [did]` in ActivityPub Person actor

### Batch 2: Federated User Cache

- `federated_users` table: cache of remote users keyed by DID + actor_uri
- `Identity.Resolver`: fetch remote profiles, verify DID operation chains
- Upsert semantics for federated user records

### Batch 3: Federated Auth Tokens + Remote Server Join

- Federated auth token: `base64url(payload).base64url(node_ed25519_signature)`
- Token verification: signature check, expiry, target instance, DID operation chain
- `federated_members` table: remote user server memberships
- `FederatedAuth` plug for extracting/verifying federated tokens
- Routes: `POST /api/v1/federation/auth-token`, `POST /api/v1/federated/join/:server_id`, etc.

### Batch 4: Multi-Instance WebSocket

- Dual auth in `UserSocket`: JWT (local) or federated token (remote)
- Federated membership checks in `ChannelChannel.join/3`
- `federated_author_id` column on messages (dual FK pattern)
- `connectionStore` (Zustand): manages `Map<domain, InstanceConnection>`
- PubSub bridge: `federated:channel:<id>` topic for local WebSocket delivery

### Batch 5: Inbox Handler + Message Federation

- Full `InboxHandler` implementation: `handle_create/2`, `handle_update/2`, `handle_delete/2`
- Author resolution: by DID (preferred) or actor_uri (fallback)
- DM guard: messages from DM channels never federated
- ActivityPub extensions: `cairn:channelId`, `cairn:did`, `cairn:homeInstance`, `cairn:displayName`
- Left-join queries in `Chat.list_messages/2` and `get_thread/2` for federated authors

### Batch 6: Client UX Polish

- `FederatedInvitePage`: remote invite flow with federated token
- `IdentityBadge`: truncated DID display with click-to-copy
- `ServerSidebar`: instance grouping, connection status indicators, "Join Remote Server" button
- `MemberList`: `@home_instance` suffix and globe icon for federated members
- `MessageList`: `@home_instance` display and globe icon for federated messages
- Federation CSS styles

---

## Key Design Decisions

1. **`did:cairn` with operation chain** -- Self-certifying, supports key rotation, no centralized registry. Operation chain stored on home instance, federated to peers.
2. **Two key pairs (signing + rotation)** -- Signing key for daily E2EE. Rotation key for identity operations only. Recovery codes as ultimate fallback.
3. **Node-signed auth tokens** -- Remote trusts the home node (already established via federation handshake). Avoids user-to-user key exchange for auth.
4. **`federated_users` is a cache** -- Home instance is authoritative. Cache refreshes on activity.
5. **Dual FK on messages** -- `author_id` OR `federated_author_id`, not polymorphic. Simple queries.
6. **DMs never federated** -- Hard rule. Simplifies privacy model enormously.
7. **`connectionStore` as coordination layer** -- Existing stores gain `instance_domain` field; new store coordinates which socket/API client to use.

---

## Test Coverage

- 355 server tests, 0 failures (up from 331 pre-Phase 9)
- 21 SFU tests, 0 failures
- 106 proto tests, 0 failures

New test files:
- `server/test/cairn/identity_test.exs` -- genesis, rotation, chain verification, tamper detection
- `server/test/cairn/federation/inbox_handler_test.exs` -- create/update/delete with DID resolution
- `server/test/cairn/federation/message_federator_test.exs` -- DM guard, federation with DID
- `server/test/cairn/federation/activity_pub_test.exs` -- DID extension fields
