# Roadmap: All-Private Channels

**Status:** Future investigation
**Goal:** Make all channels MLS-encrypted by default, with unencrypted "public" channels as a deliberate opt-out rather than the norm — and eventually eliminate unencrypted channels entirely.
**Dependencies:** Phase 2 (MLS encryption), Phase 4 (moderation/search/bots), Phase 7 (mobile).

---

## Motivation

Murmuring is a privacy-first platform, but today new channels default to unencrypted. Public channels exist because of practical limitations — mobile can't run MLS, the server can't search ciphertext, bots can't participate in MLS groups, and new members can't read history from before they joined. This roadmap identifies each blocker and lays out what's needed to resolve it, moving toward an architecture where encryption is the default for all channels.

---

## Current Blockers

### 1. Mobile MLS (Critical — complete blocker)

**Problem:** Hermes (React Native's JS engine) does not support WebAssembly. MLS is implemented via openmls compiled to WASM. If all channels are private, mobile users cannot participate in any channel.

**Resolution path:**
- **Option A: Native MLS via JSI.** Build a native module (Rust → C FFI → JSI bridge) that calls openmls directly without WASM. JSI (JavaScript Interface) allows synchronous calls to native code from JS. This is the most likely path.
- **Option B: Hermes WASM support.** Meta has discussed WASM for Hermes but no timeline. Waiting on upstream is risky.
- **Option C: Thin native binary.** Ship a small Rust binary alongside the app that handles MLS operations over a local IPC channel (Unix socket or HTTP on localhost). More complex but avoids JSI bridging.

**Estimated effort:** Large. JSI bridge for openmls requires Rust→C→ObjC/Java→JSI glue per platform, plus state serialization matching the existing TypeScript MLS interface.

**Milestone:** Mobile users can join MLS-encrypted channels and send/receive messages.

---

### 2. Message History for New Members (High — UX impact)

**Problem:** MLS provides forward secrecy. A new member can only decrypt messages from the epoch they joined onward. In public channels today, new members can scroll back through the full history. Losing this breaks onboarding, announcement archives, pinned content, and general discoverability.

**Resolution path:**
- **Option A: Sender re-encryption on join.** When a new member joins, an existing member (or a designated "history bot") re-encrypts recent history under the new epoch key and delivers it. Expensive for large histories, but preserves forward secrecy for the re-encryption window.
- **Option B: Shared history key escrow.** The group maintains a "history key" (separate from the epoch secret) that is included in MLS Welcome messages. Old messages are encrypted with epoch keys as normal, but a secondary copy of the message key is encrypted to the history key. New members can decrypt the history key from their Welcome and use it to unlock past messages. Trade-off: weakens forward secrecy for history (a compromised history key reveals all past messages).
- **Option C: Server-side encrypted archive.** Messages are stored encrypted under a long-lived channel key (not the MLS epoch key). The channel key is distributed to new members via MLS Welcome. Similar trade-off to Option B but simpler to implement.
- **Option D: Accept the limitation.** Some encrypted platforms (Signal, WhatsApp) simply don't show history to new members. For a privacy-first app, this may be acceptable — especially if admins can pin important messages that are re-encrypted for new members.

**Recommendation:** Option D as the default (accept the limitation), with Option A available as an opt-in "share recent history" action that existing members can trigger manually. This preserves forward secrecy by default while giving admins a tool for onboarding.

**Milestone:** Clear UX for "you joined on [date], messages before this are not available" plus an opt-in mechanism for admins to share selected history with new members.

---

### 3. Server-Side Search (High — significant UX cost)

**Problem:** Meilisearch indexes plaintext. Private channels are already unsearchable. Making all channels private eliminates server-side search entirely.

**Resolution path:**
- **Option A: Client-side search index.** Build a local search index (SQLite FTS5 or similar) on each client. Messages are decrypted and indexed locally. Downside: search only covers messages the client has seen, and the index doesn't sync across devices.
- **Option B: Searchable symmetric encryption (SSE).** Encrypt search tokens alongside messages so the server can match queries against encrypted tokens without learning the plaintext. Academic research exists (Song-Wagner-Perrig, Curtmola et al.) but practical implementations are complex and leak access patterns.
- **Option C: Encrypted search service.** Run a search service that holds keys in an enclave (SGX/SEV) or trusted execution environment. The server delegates search to the enclave, which decrypts, searches, and returns encrypted results. Requires hardware trust assumptions.
- **Option D: Search only your own messages.** The client maintains a local index of messages it has sent/received. Cross-channel and cross-user search is not available. Simple, private, but limited.

**Recommendation:** Option A (client-side index) as the first step — it covers the most common use case (searching your own history) with no server trust required. Option B could be investigated later for server-assisted search.

**Milestone:** Users can search their own decrypted message history across channels via a local index.

---

### 4. Bots and Webhooks (High — ecosystem impact)

**Problem:** Bots currently post to channels via simple HTTP API calls. If channels are MLS-encrypted, bots must be full MLS group members — maintaining key packages, processing commits, encrypting outgoing messages, and decrypting incoming ones.

**Resolution path:**
- **Option A: Bot MLS SDK.** Provide an openmls-based SDK (Rust or Node.js, not WASM) that bots use to participate in MLS groups. The bot manages its own key material and joins channels like any other member. Most correct approach but highest integration burden for bot authors.
- **Option B: Bot proxy service.** A server-side service that acts as an MLS-aware proxy. Bots send plaintext to the proxy via authenticated API; the proxy encrypts and sends to the channel as the bot's MLS member. Trade-off: the proxy sees bot message plaintext (but not other members' messages). Simpler for bot authors.
- **Option C: "Service member" MLS role.** Define a special MLS credential type for bots that lets them participate with reduced ceremony (e.g., automatic key package refresh, no interactive consent). Bots still do MLS but with less friction.

**Recommendation:** Option B as a bridge (gets existing bots working quickly), with Option A as the long-term target for bots that want full E2E guarantees.

**Milestone:** Existing bot/webhook integrations continue to function with minimal changes after channels become encrypted.

---

### 5. Server-Side Moderation (Medium — admin tooling regression)

**Problem:** Auto-mod (spam filters, word filters, link scanning) operates on plaintext. With all channels encrypted, the server cannot proactively scan content. Admins can only moderate based on user reports.

**Resolution path:**
- **Option A: Client-side moderation.** Move auto-mod rules to the client. The client evaluates messages locally before displaying them and can flag/report content that matches rules. The server distributes rule sets but never sees content.
- **Option B: Report-only moderation.** Accept that proactive scanning is incompatible with E2E encryption. Focus on robust reporting tools: easy report flow, mod queue with context, reputation systems, rate limiting, account-age restrictions.
- **Option C: Consent-based scanning.** Users opt-in to client-side scanning that reports hash matches (e.g., PhotoDNA for CSAM) without revealing content to the server. Controversial and technically complex.

**Recommendation:** Option B (report-only) as the baseline — this is the honest position for a privacy-first app. Supplement with Option A for spam/rate-limit rules that can run client-side without privacy cost.

**Milestone:** Admins have a clear moderation workflow that doesn't depend on reading message content.

---

### 6. MLS Churn on Large Channels (Low — performance concern)

**Problem:** Every membership change (join/leave) triggers an MLS commit that all online members must process. For large, high-turnover channels (e.g., 500+ members, open to the public), this creates continuous crypto overhead.

**Resolution path:**
- **Option A: Batched commits.** Accumulate membership changes over a short window (e.g., 5 seconds) and issue a single commit for the batch. Reduces commit frequency at the cost of slight delay.
- **Option B: Sub-groups.** Partition large channels into MLS sub-groups with a relay mechanism. Each sub-group has manageable size. Adds architectural complexity.
- **Option C: Lazy commit processing.** Clients process commits lazily (on next send/receive) rather than eagerly. Reduces CPU cost for lurkers.

**Recommendation:** Option A (batched commits) as the first optimization. Monitor real-world performance before pursuing more complex approaches.

**Milestone:** Channels with 500+ members handle join/leave churn without noticeable client-side latency.

---

## Phased Rollout

### Phase A: Private by Default
- Change the default channel type from `public` to `private` for new channels
- Add an explicit "Unencrypted Channel" option that admins must choose deliberately
- Update UI to emphasize encryption status (lock icons, explanatory text)
- Update onboarding docs and DESIGN.md
- **No blocker resolution required** — this is a UX/default change only

### Phase B: Resolve Mobile Blocker
- Implement native MLS via JSI (Blocker #1)
- Remove the "private channels unavailable on mobile" placeholder
- Mobile users can now participate in all channel types
- **Gate:** Mobile MLS passes interop tests with web/desktop MLS

### Phase C: Resolve UX Blockers
- Implement "you joined on [date]" UX + optional history sharing (Blocker #2)
- Implement client-side search index (Blocker #3)
- Implement report-only moderation workflow + client-side rule evaluation (Blocker #5)
- **Gate:** Feature parity audit — encrypted channels have equivalent UX to current public channels

### Phase D: Resolve Ecosystem Blockers
- Ship bot MLS proxy service (Blocker #4, bridge solution)
- Ship bot MLS SDK (Blocker #4, long-term solution)
- Implement batched MLS commits (Blocker #6)
- Migrate existing bot/webhook integrations
- **Gate:** All existing bots work with encrypted channels

### Phase E: Deprecate Public Channels
- Mark public channel type as deprecated in the API
- Log warnings when public channels are created
- Provide migration tooling to convert public channels to private
- Set a removal timeline (e.g., 2 major versions)

### Phase F: Remove Public Channels
- Remove `public` channel type from the schema
- Remove Meilisearch integration (or repurpose for metadata-only search)
- Remove server-side content moderation code paths
- Update all documentation

---

## Open Questions

1. **Bot proxy trust model.** The proxy service sees bot plaintext. Is this acceptable for a privacy-first platform? Should bots be required to do their own MLS?
2. **Client-side search sync.** If users have multiple devices, should search indexes sync (adding complexity and potential leakage) or remain device-local (worse UX)?
3. **Timeline for Hermes WASM.** If Meta ships WASM support in Hermes, Option A for mobile becomes much cheaper. Worth monitoring before committing to JSI.
4. **Large-channel threshold.** At what member count should batched commits activate? Needs benchmarking.
