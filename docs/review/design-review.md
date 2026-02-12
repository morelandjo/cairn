# Cairn — Design Review

**Reviewed:** 2026-02-09
**Source:** `federated-platform-plan.docx`
**Status:** Living document — update as issues are resolved during implementation

---

## Executive Summary

The design document describes a federated, privacy-first Discord alternative built on ActivityPub with E2E encryption. The architecture is sound — Elixir/Phoenix for the server, mediasoup SFU for voice, React web client, Tauri desktop, React Native mobile. However, the review identified **3 showstopper issues** and **13 significant gaps** that must be addressed before or during implementation.

The most critical structural problem was the deferral of MLS group encryption to Phase 6, which contradicted the core promise of mandatory E2E encryption for private channels. The restructured phase plan pulls MLS into Phase 2 so that private channels are never shipped without encryption.

---

## Restructured Phase Order

| Phase | Name | Duration | Change from Original |
|-------|------|----------|---------------------|
| 0 | Prerequisites & Setup | 2-3 weeks | Same |
| 1 | Core Server + E2E DMs | 8-10 weeks | No private channels — only public channels + E2E DMs |
| 2 | MLS Group Encryption + Private Channels | 6-8 weeks | **NEW** — pulled from original Phase 6 |
| 3 | Federation Protocol | 8-12 weeks | Same content, renumbered |
| 4 | Moderation, Roles & Community | 6-8 weeks | Added bots/webhooks, renumbered |
| 5 | Voice & Video (with E2E) | 6-10 weeks | Now includes E2E voice (MLS is ready) |
| 6 | Desktop, Mobile & Hardening | 8-12 weeks | Combined original Phases 5+6 |

**Total estimated timeline:** ~11-16 months (single senior developer, phases partially overlap)

---

## Issue Tracker

### Showstoppers

| # | Issue | Severity | Resolution | Phase |
|---|-------|----------|------------|-------|
| 1 | **Private channel encryption gap** — Original plan deferred MLS to Phase 6, meaning private channels would ship without E2E encryption, violating the core privacy promise | Showstopper | RESOLVED: MLS moved to Phase 2. Private channels only unlock after MLS is implemented. Phase 1 ships public channels + E2E DMs only. | 2 |
| 2 | **Account recovery is missing** — No email required (by design), but no recovery mechanism exists. Users who lose their password lose their account and all encrypted data. | Showstopper | Generate 12 recovery codes at registration (displayed once, stored hashed). Add encrypted key backup in Phase 2 (passphrase-derived key via Argon2id KDF). | 1, 2 |
| 3 | **CSAM/legal compliance** — Federated platforms face legal obligations under US 18 USC 2258A and EU CSAM Regulation. No detection or reporting mechanism was specified. | Showstopper | Hash-based detection (NCMEC/PhotoDNA) for public/unencrypted content starting in Phase 3 when federation begins. E2E encrypted content cannot be scanned (by design). | 3 |

### Significant Gaps

| # | Issue | Severity | Resolution | Phase |
|---|-------|----------|------------|-------|
| 4 | **No bot/webhook/integration system** — Platform has no way for external services to interact with it | Significant | Add incoming webhooks + bot user accounts with scoped permissions | 4 |
| 5 | **No invite system** — No mechanism for users to invite others to a server | Significant | Invite links with codes, expiration, max uses | 1 |
| 6 | **No account portability** — Users cannot migrate between nodes | Significant | RESOLVED: `did:cairn` portable cryptographic identity with self-certifying DID, hash-chained operation log, federated auth tokens, and cross-instance server joining (Phase 9). Users register once on their home instance and join servers on any federated instance without re-registering. | 9 |
| 7 | **HTTP Signatures spec deprecated** — Design references draft-cavage which is superseded | Significant | Use RFC 9421 (HTTP Message Signatures) instead | 3 |
| 8 | **No monitoring/observability** — No logging, health checks, or metrics specified | Moderate | Structured JSON logging, `/health` endpoint, Phoenix Telemetry in Phase 0/1. Prometheus + Grafana in Phase 6. | 0, 1, 6 |
| 9 | **No message formatting spec** — No specification for how messages are formatted/rendered | Moderate | Markdown subset (bold, italic, strikethrough, code, links, mentions, blockquotes) defined in protocol spec | 0, 1 |
| 10 | **No notification preferences** — No way to control notification volume | Moderate | Per-channel preferences (all / mentions / none), DND mode, quiet hours | 4 |
| 11 | **No WebSocket rate limiting** — Potential for abuse via rapid WebSocket events | Moderate | Per-connection event rate limiting with burst allowance | 1 |
| 12 | **No content delivery strategy** — No file size limits, thumbnailing, or CDN strategy | Moderate | Size limits (default 25MB), content type allowlist, per-user quota, server-side thumbnailing | 1 |
| 13 | **Redis SPOF** — Redis used for presence/PubSub with no fallback | Moderate | Graceful degradation: presence falls back to DB polling, PubSub to Phoenix.PubSub (single-node only) | 1 |
| 14 | **No protocol versioning** — No mechanism for protocol evolution or backwards compatibility | Moderate | Semver versioning in protocol spec, negotiation during federation handshake, deprecation policy | 0, 3 |
| 15 | **No data export/GDPR** — No mechanism for users to export their data (GDPR Article 20) | Moderate | `POST /api/v1/users/me/export` generates downloadable archive | 4 |
| 16 | **No server/channel discovery** — No way to find public servers | Minor | Opt-in public server directory with search | 4 |
| 17 | **No distribution/install strategy** — No plan for how operators install the server or how users get clients | Significant | One-command interactive install script, web client bundled with server, desktop via package managers + direct download, mobile via app stores + sideloading | 1, 6 |

---

## Architecture Assessment

### Strengths

- **Technology choices are well-matched:** Elixir/Phoenix is excellent for real-time WebSocket-heavy applications. The BEAM VM provides fault tolerance and concurrency. mediasoup is a proven, performant SFU.
- **Privacy-by-design is genuine:** Minimal metadata collection, no IP logging, no read receipts by default, federated envelope stripping, encrypted content opaque to server.
- **ActivityPub for federation** is pragmatic — leverages existing ecosystem and specifications rather than inventing a new protocol.
- **Layered encryption model** (X3DH + Double Ratchet for DMs, MLS for groups) follows established cryptographic patterns used by Signal and Matrix.

### Risks

- **MLS complexity:** RFC 9420 is complex and implementations are still maturing. WASM compilation adds another layer. Budget extra time for Phase 2.
- **Single-developer scope:** 11-16 months is aggressive for one developer across server, 3 clients, federation, E2E encryption, and voice. Prioritize ruthlessly — the web client is the primary client; desktop and mobile are stretch goals.
- **Federation testing:** Two-node testing is necessary but insufficient. Real-world federation involves latency, partial failures, and byzantine behavior. The staging environment should be expanded over time.
- **WebRTC + E2E via Insertable Streams:** Browser support for Insertable Streams is evolving. Firefox support is behind Chrome. Plan for graceful degradation.

### Recommendations

1. **Ship Phase 1 as the MVP.** A working server with public channels, E2E DMs, and a web client has standalone value.
2. **Phase 2 is the hardest phase.** MLS + WASM is the highest technical risk. Prototype early, fail fast.
3. **Protocol spec is a gating dependency.** Don't start Phase 1 implementation until the protocol spec from Phase 0 is at least draft-complete.
4. **Automate federation testing.** The two-node Docker Compose setup should have scripted test scenarios that run in CI.

---

## Cross-Phase Dependencies

```
Phase 0 ──→ Phase 1 ──→ Phase 2 ──→ Phase 3/3.5
                │            │           │
                │            │           ├──→ Phase 4
                │            │           │
                │            ├───────────┼──→ Phase 5
                │                        │
                └────────────────────────┼──→ Phase 6 ──→ Phase 7
                                         │
                                         ├──→ Phase 8
                                         │
                                         └──→ Phase 9

Key dependencies:
  Phase 1 → Phase 2: Identity keys (Ed25519) become MLS credentials
  Phase 2 → Phase 5: MLS group keys used for E2E voice encryption
  Phase 3 → Phase 4: Federation required for federated moderation
  Phase 3.5 → Phase 9: Federation infra required for portable identity
  Phase 9: Ed25519 identity keys → DID, federation handshake → federated auth tokens
  Phase 0 → All:     Protocol spec is the foundation for everything
```

---

## Issue Resolution Checklist

Use this to track which issues have been addressed during implementation:

- [x] #1 — Private channel encryption gap (Phase 2)
- [x] #2 — Account recovery (Phase 1: codes, Phase 2: key backup)
- [x] #3 — CSAM/legal compliance (Phase 3)
- [x] #4 — Bot/webhook system (Phase 4)
- [x] #5 — Invite system (Phase 1)
- [x] #6 — Account portability (Phase 9: `did:cairn` portable identity)
- [x] #7 — RFC 9421 HTTP Signatures (Phase 3.5)
- [x] #8 — Monitoring/observability (Phase 0/1/8)
- [x] #9 — Message formatting spec (Phase 0/1)
- [x] #10 — Notification preferences (Phase 4)
- [x] #11 — WebSocket rate limiting (Phase 1)
- [x] #12 — Content delivery strategy (Phase 1)
- [x] #13 — Redis SPOF (Phase 1)
- [x] #14 — Protocol versioning (Phase 0/3)
- [x] #15 — Data export/GDPR (Phase 4)
- [x] #16 — Server/channel discovery (Phase 4)
- [x] #17 — Distribution/install strategy (Phase 8: install script, SPA serving, desktop CI, mobile EAS)
