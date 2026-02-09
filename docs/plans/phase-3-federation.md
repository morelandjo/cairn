# Phase 3: Federation Protocol

**Duration:** 8-12 weeks
**Goal:** Nodes discover each other, verify identity, and federate channels and messages. Privacy metadata is minimized at federation boundaries.
**Dependencies:** Phase 2 complete (MLS encryption working, private channels functional). Federation handles both encrypted and unencrypted content.
**Deliverable:** Two or more Murmuring nodes can federate — users on different nodes can participate in shared channels with full message delivery, editing, deletion, and causal ordering.

---

## Review Issues Addressed

- **#3 — CSAM/legal compliance:** Hash-based detection for public/unencrypted content
- **#6 — Account portability:** Data export for node migration (started here, completed in Phase 4)
- **#7 — HTTP Signatures spec deprecated:** Use RFC 9421 instead of draft-cavage
- **#14 — Protocol versioning:** Version negotiation during federation handshake

---

## Tasks

### Node Identity & Discovery

- [ ] **3.1** Node signing key pair:
  - Generate Ed25519 key pair on first boot
  - Store private key securely (configurable path via `NODE_KEY_PATH` env var, default: `priv/keys/node.key`)
  - Key is used to sign all outbound federated messages
  - Operator-accessible backup documentation

- [ ] **3.2** TLS certificate management:
  - Option A: Automatic Let's Encrypt via ACME client (e.g., `site_encrypt` Elixir library)
  - Option B: Manual certificate configuration via env vars (`TLS_CERT_PATH`, `TLS_KEY_PATH`)
  - mTLS for node-to-node communication (mutual certificate verification)
  - Certificate rotation support without downtime

- [ ] **3.3** Well-known federation endpoint:
  ```
  GET /.well-known/federation
  ```
  Returns JSON:
  ```json
  {
    "node_id": "<uuid>",
    "public_key": "<base64-encoded-ed25519-pubkey>",
    "protocol_version": "1.0.0",
    "supported_versions": ["1.0.0"],
    "domain": "murmuring.example.com",
    "software": "murmuring",
    "software_version": "0.1.0",
    "privacy_manifest": {
      "version": "1.0",
      "logging": { "ip_addresses": false, "message_content": false },
      "retention": { "messages_days": 365, "files_days": 90 },
      "federation": { "metadata_stripped": true, "read_receipts": false }
    }
  }
  ```

- [ ] **3.4** Node registration flow:
  1. Operator adds remote node URL via admin API: `POST /api/v1/admin/federation/nodes`
  2. Server fetches remote `/.well-known/federation`
  3. Verify TLS certificate
  4. Store remote node's public key + metadata
  5. Initiate mTLS handshake
  6. Remote node reciprocates (if configured to accept)
  7. Both nodes are now federated peers

- [ ] **3.5** WebFinger (RFC 7033):
  ```
  GET /.well-known/webfinger?resource=acct:username@node.example.com
  ```
  Returns:
  ```json
  {
    "subject": "acct:username@node.example.com",
    "links": [
      {
        "rel": "self",
        "type": "application/activity+json",
        "href": "https://node.example.com/users/username"
      }
    ]
  }
  ```

- [ ] **3.6** Protocol version negotiation:
  - Nodes advertise supported versions in `/.well-known/federation`
  - During handshake, negotiate highest common version
  - If no common version exists, federation is rejected with clear error
  - Deprecation: nodes warn when using a version marked for deprecation

### ActivityPub Implementation

- [ ] **3.7** ActivityPub inbox:
  - `POST /inbox` — server-level inbox for federated activities
  - `POST /users/:id/inbox` — user-level inbox (for DMs, mentions)
  - Content-Type: `application/activity+json`
  - Verify HTTP Signature before processing any activity
  - Queue processing via Oban (don't block the HTTP response)

- [ ] **3.8** ActivityPub outbox:
  - `GET /users/:id/outbox` — list of public activities by user
  - Paginated (ActivityStreams OrderedCollection)
  - Only includes public channel messages (not DMs, not private channel content)

- [ ] **3.9** Custom ActivityPub object types:
  - `MurmuringServer` — represents a server/guild, extends AP `Group`
  - `MurmuringChannel` — represents a channel, includes type (public/private) and encryption status
  - `MurmuringMessage` — extends AP `Note`, includes optional `encryptedContent` field, HLC timestamp
  - `MurmuringReaction` — extends AP `Like`, includes emoji field
  - All types documented in protocol spec with JSON-LD context

- [ ] **3.10** Follow/Accept flow for channel subscription:
  1. Remote user wants to join a federated public channel
  2. Remote user's home node sends `Follow` activity to hosting node
  3. Hosting node evaluates permissions (public channel → auto-accept, or require approval)
  4. Hosting node sends `Accept` (or `Reject`) activity back
  5. On Accept: remote user is added to channel member list with `remote` flag
  6. Hosting node begins sending channel messages to remote node's inbox

- [ ] **3.11** Message federation:
  - Message posted to channel with remote subscribers:
    1. Persist message locally
    2. Wrap in `Create` activity
    3. For each subscribed remote node, enqueue delivery to node's inbox
    4. Include HLC timestamp and cryptographic signature in activity

- [ ] **3.12** RFC 9421 HTTP Message Signatures:
  - Sign outbound requests with node's Ed25519 private key
  - Signature covers: `(request-target)`, `host`, `date`, `digest`, `content-type`
  - Receiving node verifies signature against known public key
  - Reject unsigned or invalid-signature requests with 401
  - **Do NOT use deprecated draft-cavage** — use RFC 9421 exclusively

- [ ] **3.13** Remote user identity verification:
  - On receiving a federated activity:
    1. Extract signer from HTTP Signature
    2. Look up signer's public key (cached from federation handshake)
    3. Verify signature
    4. Verify actor in activity matches signer's node
  - Cache public keys with TTL (refresh from `/.well-known/federation` periodically)

### Delivery & Consistency

- [ ] **3.14** Oban delivery queue:
  - `FederationDeliveryWorker` Oban job for outbound federation
  - Configurable retry: exponential backoff (1s, 2s, 4s, 8s, ..., max 1h between retries)
  - Max retry duration: 72 hours, then mark as failed
  - Dead letter queue for permanently failed deliveries
  - Per-node delivery tracking: success rate, average latency, error counts

- [ ] **3.15** Hybrid Logical Clock (HLC) timestamps:
  - Implementation: wall clock time + logical counter
  - `{wall_time_ms, logical_counter, node_id}`
  - On local event: `HLC.now()` — max(wall_clock, last_hlc.wall) + increment counter
  - On receiving remote event: `HLC.update(remote_hlc)` — max(local, remote) + increment
  - All messages stamped with HLC for causal ordering

- [ ] **3.16** Edit propagation:
  - `Update` activity sent to all subscribed nodes when a message is edited
  - Include: original message ID, new content, edit timestamp
  - Configurable edit window: edits older than N hours (default: 48h) are rejected
  - Remote nodes apply edit if message exists locally and edit is within window

- [ ] **3.17** Delete propagation:
  - `Delete` activity sent immediately to all subscribed nodes
  - Remote nodes soft-delete the message (same as local: clear content, keep tombstone)
  - Tombstone retained for sync consistency, eventual hard-delete after retention period

- [ ] **3.18** Ephemeral message TTL:
  - Optional `ttl` field on messages (seconds until auto-delete)
  - Federated as part of the activity
  - Oban sweep job: runs every 5 minutes, hard-deletes expired messages
  - Remote nodes honor TTL independently

- [ ] **3.19** HLC tiebreaking:
  - Same-timestamp messages: ordered by `node_id` (lexicographic) then `message_id`
  - Deterministic ordering across all nodes for identical HLC values
  - Client-side: sort messages by HLC, break ties consistently

### Metadata & Privacy

- [ ] **3.20** Metadata stripping:
  - Outbound federation activities include ONLY:
    - Message ID, author (`username@node`), channel ID, content (plaintext or ciphertext), HLC timestamp, signature
  - Stripped before sending:
    - IP addresses, user agent, device fingerprint, client version
    - Read receipt status, typing indicators
    - Internal database IDs, internal user metadata

- [ ] **3.21** Federated envelope format:
  ```json
  {
    "@context": ["https://www.w3.org/ns/activitystreams", "https://murmuring.dev/ns"],
    "type": "Create",
    "actor": "https://node-a.example.com/users/alice",
    "object": {
      "type": "MurmuringMessage",
      "id": "https://node-a.example.com/messages/<uuid>",
      "attributedTo": "https://node-a.example.com/users/alice",
      "inReplyTo": null,
      "content": "Hello from node A!",
      "hlcTimestamp": { "wall": 1700000000000, "counter": 0, "node": "node-a" },
      "published": "2026-03-01T12:00:00Z"
    },
    "to": ["https://node-b.example.com/channels/<uuid>"]
  }
  ```

- [ ] **3.22** Opt-in read receipts:
  - Disabled across federation by default
  - Configurable per-node: operator can enable federated read receipts
  - Same-node read receipts: opt-in per user (Settings → Privacy)
  - Never included in federated activities unless both nodes explicitly opt in

- [ ] **3.23** CSAM hash detection:
  - For public/unencrypted content only (encrypted content CANNOT be scanned — by design)
  - Integrate with NCMEC hash list or PhotoDNA-compatible service
  - Hash uploaded images (perceptual hash) and compare against known CSAM hashes
  - On match: block upload, log for operator review, report per legal requirements
  - **E2E encrypted content is exempt** — the server never has access to plaintext

- [ ] **3.24** GDPR data deletion across federation:
  - When a user requests data deletion:
    1. Delete all local data
    2. Send `Delete` activities for all the user's federated content
    3. Remote nodes process deletion (best-effort — cannot force remote compliance)
  - Log deletion requests for compliance audit trail

### Defederation & Federation Moderation

- [ ] **3.25** Node-level blocking (defederation):
  - Admin API: `POST /api/v1/admin/federation/nodes/:id/block`
  - On block:
    1. Stop all outbound message delivery to blocked node
    2. Reject all inbound activities from blocked node
    3. Optionally: remove cached remote content from blocked node
  - Unblock: `POST /api/v1/admin/federation/nodes/:id/unblock` — resume federation

- [ ] **3.26** Privacy manifest validation:
  - On federation handshake, compare remote node's privacy manifest against configurable minimums
  - Example: require `"logging.ip_addresses": false` and `"retention.messages_days" <= 365`
  - Auto-reject nodes that don't meet minimum standards (configurable)
  - Warning mode: accept but flag to operator

- [ ] **3.27** Inbound federation rate limiting:
  - Per-node rate caps: max N activities per minute (configurable, default: 100/min)
  - Burst allowance for catch-up after downtime
  - Exceeded → 429 Too Many Requests → remote node should back off
  - Persistent offenders → automatic temporary block with operator notification

- [ ] **3.28** Federated spam detection:
  - Heuristics for inbound federated messages:
    - Rapid-fire messages from single remote user
    - High volume of identical content across channels
    - New remote users sending links immediately
  - Actions: quarantine message for moderator review, rate-limit remote user, notify operator
  - Configurable thresholds and actions

- [ ] **3.29** Admin federation dashboard:
  - Web UI page for operators:
    - List of federated nodes with status (active, blocked, offline)
    - Privacy manifests for each node
    - Block/unblock controls
    - Delivery queue health: pending, failed, dead-lettered
    - Federation metrics: messages in/out per node, latency, error rates
    - Node health timeline: uptime/downtime history

### Web Client Updates

- [ ] **3.30** Federated user display:
  - Local users: `username` (plain)
  - Remote users: `username@node.example.com` (with subtle remote indicator)
  - User profile: shows home node, federation status

- [ ] **3.31** Privacy manifest display:
  - When joining a federated channel, show the hosting node's privacy manifest
  - Highlight differences from local node's policy
  - User consent: "This channel is hosted on node-b.example.com. Their privacy policy differs: [details]. Join anyway?"

- [ ] **3.32** Federation UX indicators:
  - Message delivery status: sent → delivered to local server → federated to remote nodes
  - Remote node offline: warning icon on federated channels, "Messages will be delivered when node comes back online"
  - Defederation notification: "This server has disconnected from node-b.example.com"

---

## Testing Checkpoint

- [ ] Two nodes via Docker Compose (staging environment from Phase 0):
  - Register user on each node
  - Federate the two nodes via admin API
  - Create public channel on node-a, subscribe from node-b
  - Send messages both directions — verify delivery
- [ ] HLC ordering: send messages from both nodes rapidly, verify consistent ordering on both sides
- [ ] Edit propagation: edit message on node-a → verify edit appears on node-b
- [ ] Delete propagation: delete message on node-b → verify deletion on node-a
- [ ] Defederation test:
  - Block node-b from node-a
  - Verify: no messages delivered from node-a to node-b
  - Verify: node-b's messages rejected by node-a
  - Unblock → verify federation resumes
- [ ] Node offline recovery:
  - Stop node-b → send messages on federated channel → start node-b → verify queued messages deliver
- [ ] Metadata verification: inspect federated activity payloads, confirm no IP/device/client data present
- [ ] HTTP Signature verification: tamper with a federated message → verify it's rejected
- [ ] Rate limiting: flood node-a from node-b → verify rate limiting kicks in
- [ ] Protocol version: test with mismatched versions → verify negotiation or graceful rejection

---

## Notes

- Federation is inherently complex. Budget the full 12 weeks if possible.
- The two-node staging environment is the primary testing tool. Consider adding a third node for multi-hop testing.
- Private channel messages are federated as ciphertext — remote nodes relay but cannot read. The MLS group manages access.
- Account portability (export user data + identity keys) is started here but the full migration flow is in Phase 4.
- CSAM detection only applies to unencrypted public content. This is a deliberate design choice — scanning encrypted content would break E2E encryption guarantees.
