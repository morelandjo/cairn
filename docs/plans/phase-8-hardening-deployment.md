# Phase 8: Security Hardening, Deployment & Distribution

**Duration:** 4-6 weeks
**Goal:** Security hardening, production deployment tooling, and distribution infrastructure for server operators and end users.
**Dependencies:** Phase 6 (desktop), Phase 7 (mobile) — some tasks can be parallelized.
**Deliverable:** Hardened server, production Docker images, one-command install, monitoring, and client distribution via package managers and app stores.

---

## Review Issues Addressed

- **#8 — Monitoring/observability:** Prometheus metrics, Grafana dashboards, distributed tracing

---

## Tasks

### Security Hardening

- [ ] **8.1** Threat model document (`docs/security/threat-model.md`):
  - Trust boundaries: client ↔ server, server ↔ SFU, server ↔ federation, server ↔ database
  - Attack surfaces: auth endpoints, WebSocket, federation inbox, file upload, voice signaling
  - Threat actors: malicious users, compromised nodes, network attackers, compromised server
  - Mitigations: per-surface, mapped to implementation
  - Assumptions: server operator is trusted for metadata (but not message content), remote nodes are partially trusted

- [ ] **8.2** API rate limiting:
  - `Hammer` library or custom `Plug` with ETS backend
  - Auth endpoints: 5 attempts/min/IP for login, 3/hour for registration
  - General API: 100 req/min/user
  - File upload: 10/min/user
  - Return `429 Too Many Requests` with `Retry-After` header

- [ ] **8.3** Security headers:
  - CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' wss:`
  - HSTS: `max-age=31536000; includeSubDomains`
  - `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`
  - Implemented as a Plug in the Phoenix pipeline

- [ ] **8.4** Audit logging:
  - Events: auth (login, logout, failed attempts, 2FA changes), role changes, federation handshakes, defederation, server settings, moderation actions
  - `audit_logs` table: `event_type`, `actor_id`, `target_id`, `metadata` (JSONB), `ip_address` (configurable), `inserted_at`
  - Operator-only access, 90-day default retention, auto-pruned via Oban job

- [ ] **8.5** Node signing key rotation:
  - `POST /api/v1/admin/federation/rotate-key` — generate new key pair
  - Grace period: 7 days with both old and new key in `/.well-known/federation`
  - Notify federated peers via ActivityPub `Update` activity
  - Document rotation procedure

- [ ] **8.6** Automated security scanning in CI:
  - Elixir: `sobelow` (static security analysis)
  - Node.js: `npm audit`
  - Rust: `cargo audit`
  - Fail CI on high/critical vulnerabilities
  - Weekly scheduled scan for new vulnerabilities

- [ ] **8.7** Third-party security audit:
  - Commission professional audit before public beta
  - Scope: server API, authentication, E2E encryption, federation protocol, WebSocket handling
  - Remediate all critical/high findings before release

- [ ] **8.8** Security disclosure program:
  - `SECURITY.md` — reporting process, response timeline (48h ack, 1-week triage), safe harbor

### Deployment

- [ ] **8.9** Official Docker images:
  - Phoenix server: Alpine-based, multi-stage build, <100MB target
  - SFU: Node.js Alpine, mediasoup native deps, <200MB target
  - Published to Docker Hub or GHCR, tags: `latest`, semver, `main`

- [ ] **8.10** Production Docker Compose (`deploy/docker-compose.prod.yml`):
  - Services: Phoenix, SFU, PostgreSQL, Redis, Meilisearch
  - `.env` file configuration (template as `.env.example`)
  - Volume mounts, resource limits, restart policy, health checks

- [ ] **8.11** Ansible playbooks (`deploy/ansible/`):
  - Target: single VPS ($5/month, 1 vCPU, 1GB RAM)
  - `setup.yml` — Docker, firewall, swap
  - `deploy.yml` — pull images, start services, run migrations, verify health
  - `backup.yml` — automated backup
  - `update.yml` — rolling restart with migrations

- [ ] **8.12** Disk encryption documentation:
  - LUKS full-disk encryption guide for Linux VPS
  - Key management, remote unlock via dropbear SSH

- [ ] **8.13** Automated backup:
  - Mix task: `mix cairn.backup` (pg_dump + file archive + optional key archive)
  - Encrypted with operator key (AES-256-GCM)
  - Upload to local path, S3, or rsync
  - `mix cairn.restore` for restore
  - Oban scheduled job for daily backup

- [ ] **8.14** Prometheus metrics endpoint:
  - `GET /metrics` — Prometheus-compatible
  - Metrics: HTTP latency, WebSocket connections, Ecto queries, federation stats, voice stats, BEAM VM stats
  - Implementation via `PromEx` or `Telemetry.Metrics`

- [ ] **8.15** Grafana dashboard templates (`deploy/grafana/`):
  - Overview, Federation, Voice, Database, System dashboards
  - JSON definitions importable into Grafana

- [ ] **8.16** Structured logging with correlation IDs:
  - UUID per HTTP request (`X-Request-ID`), propagated to Ecto, Oban, WebSocket, federation
  - Document setup with Loki, ELK, or hosted services

### Distribution — Server

- [ ] **8.17** Interactive install script (`deploy/install.sh`):
  - One-command: `curl -sSL https://get.cairn.chat/install | sh`
  - Prerequisites check: Docker, Docker Compose, ports, disk space, OS compatibility
  - Interactive wizard: domain, TLS (Let's Encrypt), storage, admin account, federation, voice, resource limits
  - Writes `.env` + `cairn.yml`, pulls images, starts services, runs migrations

- [ ] **8.18** Advanced / non-interactive install:
  - `install.sh --config /path/to/cairn.yml` — skip wizard
  - `install.sh --env /path/to/.env` — skip wizard
  - `--json` flag for machine-readable output
  - Docker Compose override support

- [ ] **8.19** Operator CLI tool (`cairn-ctl`):
  - Commands: `status`, `upgrade`, `backup`, `restore`, `federation list/add`, `user create/reset-password`, `config set`, `logs`
  - Mix task suite with Docker exec shell wrapper

- [ ] **8.20** Package manager distribution (server):
  - Homebrew tap, AUR PKGBUILD, Nix flake, apt/deb repo
  - All use Docker under the hood — packages provide orchestration + `cairn-ctl`

- [ ] **8.21** Upgrade path:
  - `cairn-ctl upgrade` — auto backup, version check, pull images, migrate, verify
  - `cairn-ctl rollback` — revert to previous image tags + restore backup
  - Release notes displayed before confirmation

### Distribution — Web Client

- [ ] **8.22** Web client served by Phoenix:
  - `client/web/dist/` embedded into Phoenix release as static assets
  - SPA served at `/` with catch-all route
  - Hashed filenames with immutable cache, `index.html` with no-cache

- [ ] **8.23** Web client configuration injection:
  - Phoenix renders `<script>` with `window.__CAIRN_CONFIG__` in `index.html`
  - Config: instance name, domain, branding, feature flags, upload limits

### Distribution — Desktop

- [ ] **8.24** Desktop download page:
  - Auto-detect OS, GitHub Releases links
  - macOS `.dmg`, Windows `.msi`, Linux `.AppImage` + `.deb`
  - SHA-256 checksums

- [ ] **8.25** Desktop package managers:
  - Homebrew Cask, Winget, Flathub, AUR, evaluate Snap
  - CI: automate submissions on release

- [ ] **8.26** Desktop first-run experience:
  - "Connect to a Cairn server" → enter server URL
  - Server list: remember previously connected servers
  - Deep link handling: `cairn://invite/...` opens app and joins

### Distribution — Mobile

- [ ] **8.27** App Store submission (iOS):
  - EAS Build + Submit, TestFlight beta
  - Privacy nutrition labels: E2E encryption, minimal data collection
  - Review: explain federation model, emphasize E2E encryption

- [ ] **8.28** Play Store submission (Android):
  - EAS Build + Play Console, internal → closed → open → production
  - APK on GitHub Releases for sideloading (F-Droid compatibility)
  - Data safety section: E2E encryption, minimal data collection

- [ ] **8.29** Mobile server connection:
  - First launch: server URL prompt
  - QR code scan option from server web UI
  - Multi-server support, push token per-server

---

## Testing Checkpoint

- [ ] Security:
  - Penetration test (professional or OWASP checklist self-assessment)
  - Rate limiting: auth endpoints protected
  - Security headers: pass Mozilla Observatory
  - Sobelow/npm audit/cargo audit: no high/critical issues

- [ ] Deployment:
  - 2 VPS instances deployed via Ansible
  - Full integration: federation + encryption + voice across 2 nodes
  - Backup + restore round-trip
  - Prometheus + Grafana: all metrics flowing

- [ ] Server installation:
  - Fresh VPS (Debian/Ubuntu/Fedora): install script → wizard → running with HTTPS
  - Non-interactive install with config file
  - Upgrade + rollback cycle verified
  - All `cairn-ctl` commands work

- [ ] Client distribution:
  - Web client served at `/` on any instance
  - Desktop installs and launches on macOS, Windows, Linux
  - Mobile installs from TestFlight / Play internal track
  - Push notifications work, deep links work

- [ ] Scalability:
  - MLS with 50+ members
  - 100+ concurrent WebSocket connections
  - E2E voice latency acceptable across all platforms

---

## Notes

- This phase is the final gate before public release.
- Third-party security audit (task 8.7) has a 4-8 week lead time — start the engagement early.
- The $5/month VPS target is for small communities (<100 users). Document scaling for larger deployments.
- The install script is the first thing most operators interact with — it should be polished and handle edge cases.
- The web client is bundled with the server — no separate web deployment needed.
- Code signing (macOS notarization, Windows Authenticode) is required for desktop distribution.
- Cross-platform desktop release pipeline (GitHub Actions matrix builds) is implemented here, not in Phase 6.
