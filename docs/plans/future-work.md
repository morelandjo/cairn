# Future Work Tracker

Items identified across all documentation as planned, not yet implemented, or deferred.

---

## Critical

### 1. Mobile MLS E2EE
**Source:** DESIGN.md §13, FAQ.md, CLIENT.md, all-private-channels-roadmap.md
**Problem:** Hermes (React Native JS engine) doesn't support WebAssembly. MLS is compiled via openmls → WASM. Mobile users cannot participate in private (encrypted) channels at all.
**Options:** Native MLS via JSI, wait for Hermes WASM support, thin native binary with local IPC.
**Blocks:** All-private channels initiative (Phase B).

### 2. Instance Migration Protocol
**Source:** DESIGN.md §13, FAQ.md Q5
**Problem:** Users survive instance loss for existing connections but cannot move their DID to a new home instance. Key bundles, channel memberships, and message history don't transfer.
**Options:** DID operation chain entry for migration, coordinated transfer protocol between old and new home instance.

### 3. CSAM Detection in Encrypted Content
**Source:** DESIGN.md §13, design-review.md #3
**Problem:** Server cannot scan encrypted content for child sexual abuse material. Legal obligations exist under US 18 USC 2258A and EU CSAM Regulation.
**Options:** Client-side hash-matching (PhotoDNA/NCMEC), consent-based scanning. No solution implemented.
**Note:** Fundamental tension between privacy and safety. Public/unencrypted content scanning exists (Phase 3).

---

## High

### 4. Private Channel Search
**Source:** DESIGN.md §13, all-private-channels-roadmap.md blocker #3
**Problem:** Meilisearch indexes plaintext only. Users in private channels cannot search their own message history server-side.
**Options:** Client-side search index (SQLite FTS5), searchable symmetric encryption (SSE), encrypted search via TEE enclave.

### 5. Linux Desktop Voice E2E Encryption
**Source:** DESIGN.md §13, webrtc-webview-matrix.md
**Problem:** WebKitGTK does not support Insertable Streams. Linux desktop users get voice without end-to-end encryption (DTLS-SRTP protects transport only).
**Depends on:** WebKitGTK upstream adding Insertable Streams support.

### 6. Scale Testing
**Source:** DESIGN.md §13
**Problem:** Not tested beyond small-to-medium deployments. Unknown behavior at scale for MLS group operations, federation delivery, and SFU with hundreds of concurrent voice participants.
**Action:** Load testing suite, benchmarks for MLS commit processing, federation delivery throughput, SFU capacity limits.

### 7. Third-Party Security Audit
**Source:** phase-8-hardening-deployment.md
**Problem:** No external security audit has been conducted. 4-8 week lead time noted.
**Action:** Engage auditor for server, crypto implementation, federation protocol.

### 8. Automated Federation Testing
**Source:** design-review.md recommendations, risks section
**Problem:** Two-node testing is necessary but insufficient. Real-world federation involves latency, partial failures, and byzantine behavior.
**Action:** Scripted two-node test scenarios in CI, expanded staging environment.

---

## Medium

### 9. Bot/Webhook MLS Support
**Source:** all-private-channels-roadmap.md blocker #4
**Problem:** Bots post to channels via simple HTTP. If channels are MLS-encrypted, bots must be full MLS group members or use a proxy.
**Options:** Bot MLS SDK (Rust/Node.js), bot proxy service (server sees bot plaintext), "service member" MLS credential type.
**Blocks:** All-private channels initiative (Phase D).

### 10. Server-Side Moderation for Encrypted Channels
**Source:** all-private-channels-roadmap.md blocker #5
**Problem:** Auto-mod (spam filters, word filters, link scanning) operates on plaintext. Cannot scan encrypted content.
**Options:** Client-side rule evaluation, report-only moderation, consent-based scanning.
**Blocks:** All-private channels initiative (Phase C).

### 11. Message History for New Members in Encrypted Channels
**Source:** all-private-channels-roadmap.md blocker #2
**Problem:** MLS forward secrecy means new members cannot decrypt messages from before they joined. Breaks onboarding, announcement archives, pinned content.
**Options:** Sender re-encryption on join, shared history key escrow, server-side encrypted archive, accept the limitation.
**Blocks:** All-private channels initiative (Phase C).

### 12. MLS Batched Commits for Large Channels
**Source:** all-private-channels-roadmap.md blocker #7
**Problem:** Every join/leave triggers an MLS commit all online members must process. High churn on 500+ member channels creates continuous crypto overhead.
**Options:** Batched commits (short window), sub-groups with relay, lazy commit processing.
**Blocks:** All-private channels initiative (Phase D).



---

## Low

### 14. Custom Emoji in Protocol Spec
**Source:** protocol-spec.md §9.3
**Problem:** "Custom emoji are out of scope for protocol version `0.1.0` and will be defined in a future version." Implementation exists (Phase 4) but the wire format is not in the spec.
**Action:** Add custom emoji format to protocol spec for version 0.2.0.

