# Phase 6: Desktop, Mobile & Hardening

**Duration:** 8-12 weeks
**Goal:** Native clients for all platforms, security hardening, production deployment, and distribution for both server operators and end users.
**Dependencies:** All prior phases complete. This is the final phase before public release.
**Deliverable:** Desktop (Tauri) and mobile (React Native) clients with full feature parity, security hardening, production-ready deployment, and a one-command server install experience.

---

## Review Issues Addressed

- **#8 — Monitoring/observability:** Prometheus metrics, Grafana dashboards, distributed tracing

---

## Tasks

### Shared Code Extraction

- [ ] **6.1** Extract shared business logic from web client into `proto/` package:
  - API client (REST + WebSocket wrapper)
  - State management (zustand stores for auth, channels, messages, presence, voice)
  - Message formatting (Markdown parsing, mention resolution)
  - Crypto utilities (X3DH, Double Ratchet, MLS wrapper)
  - WebSocket management (connection, reconnection, channel subscription)
  - File encryption/decryption utilities
  - All shared code must be platform-agnostic (no DOM, no `window`, no `navigator` references)

- [ ] **6.2** Shared test suite:
  - Unit tests for all extracted shared code
  - Run in Node.js (not browser) to verify platform independence
  - Tests cover: API client mocking, store state transitions, crypto operations, message formatting
  - CI: shared tests run on every push

### Desktop (Tauri)

- [ ] **6.3** Tauri project setup (`client/desktop/`):
  - Tauri v2 with web frontend from `client/web/`
  - Build config: target macOS (Universal Binary), Windows (x64 + ARM64), Linux (AppImage + .deb)
  - Rust backend for native APIs (file system, keychain, notifications, global shortcuts)
  - Development: `tauri dev` with hot reload of web frontend

- [ ] **6.4** System tray:
  - Tray icon with unread count badge (macOS, Windows, Linux)
  - Tray menu: Open, Mute Notifications, Quit
  - Click tray icon: show/hide main window
  - Minimize to tray (configurable: close button minimizes to tray vs. quits)

- [ ] **6.5** Native desktop notifications:
  - OS-level notifications via Tauri notification plugin
  - Notification content: channel name + "New message from [username]" (never message content for privacy)
  - Click notification → open app to relevant channel
  - Respect notification preferences (per-channel, DND mode)

- [ ] **6.6** Global keyboard shortcuts:
  - Push-to-talk key: configurable global hotkey (works even when app not focused)
  - Toggle mute: configurable global hotkey
  - Toggle deafen: configurable global hotkey
  - Registration: Tauri global shortcut plugin, conflict detection

- [ ] **6.7** Auto-start on login:
  - Configurable in Settings → Application
  - Implementation: Tauri auto-start plugin (login items on macOS, startup folder on Windows, autostart on Linux)
  - Start minimized to tray option

- [ ] **6.8** OS keychain integration:
  - macOS: Keychain Services (via `security-framework` Rust crate)
  - Windows: Credential Manager (via `windows-credentials` Rust crate)
  - Linux: Secret Service D-Bus API (via `secret-service` Rust crate, falls back to file-based encrypted storage)
  - Store: E2E private keys (identity key, signed prekey), MLS state, auth tokens
  - Migration: on first launch, offer to move keys from IndexedDB to OS keychain

- [ ] **6.9** Auto-update:
  - Tauri updater plugin with update server
  - Release pipeline (GitHub Actions):
    1. Build for all platforms (macOS Universal, Windows x64/ARM64, Linux AppImage/deb)
    2. Code sign (macOS notarization, Windows Authenticode)
    3. Publish release artifacts to GitHub Releases
    4. Publish update manifest (JSON with version, download URLs, signatures)
  - Client: check for updates on launch + periodically, prompt user to install
  - Rollback: if update fails, revert to previous version

- [ ] **6.10** Deep linking:
  - `murmuring://` protocol handler
  - Use cases: invite links (`murmuring://invite/<code>`), channel links (`murmuring://channel/<id>`)
  - Registration: OS protocol handler via Tauri
  - Web fallback: if desktop app not installed, redirect to web client

- [ ] **6.11** WebRTC voice testing across webview engines:
  - WebView2 (Windows): test audio/video, Insertable Streams support
  - WebKit (macOS): test audio/video, check Insertable Streams support (may need fallback)
  - WebKitGTK (Linux): test audio/video, check Insertable Streams support
  - Document known issues and workarounds per platform
  - Audio device enumeration: verify all webview engines support `enumerateDevices()`

### Mobile (React Native / Expo)

- [ ] **6.12** Expo project setup (`client/mobile/`):
  - Expo SDK (latest stable) with development build (not Expo Go — need native modules)
  - Dependencies: expo-router (navigation), expo-secure-store, react-native-webrtc, sodium-react-native
  - Shared `proto/` package linked as dependency
  - Build: EAS Build for iOS and Android

- [ ] **6.13** Mobile UI:
  - Tab navigation: Channels, DMs, Search, Settings
  - Channel list: swipe to mark read/mute
  - Message view: pull-to-refresh for history, auto-scroll for new messages
  - Swipe gestures: swipe right on message to reply, long-press for context menu (react, pin, delete)
  - Adaptive layout: iPhone SE to iPad Pro, Android phone to tablet
  - Dark mode: follow system preference or manual toggle

- [ ] **6.14** Push notifications:
  - Via Expo Push Notifications or self-hosted ntfy
  - **Privacy-first payload:** `{ "channel_id": "<uuid>", "count": 1 }` — NEVER include message content, sender name, or any identifiable information
  - On receive: update badge count, show generic notification ("New message in [channel name]")
  - Notification tap: open app to relevant channel
  - Token registration: `POST /api/v1/users/me/push-tokens`

- [ ] **6.15** Voice via react-native-webrtc:
  - Test on physical iOS and Android devices (simulators have audio issues)
  - Audio session management: handle interruptions (phone call, other apps), audio routing (speaker, earpiece, Bluetooth)
  - Background audio: keep voice connected when app is backgrounded
  - Call UI: proximity sensor (turn off screen when held to ear), in-call notification

- [ ] **6.16** Secure key storage:
  - `expo-secure-store`: wraps iOS Keychain and Android Keystore
  - Store: E2E private keys, MLS state, auth tokens
  - Biometric protection: require Face ID/fingerprint to access keys (configurable)
  - Key size limit: expo-secure-store has 2KB limit per item → serialize and chunk larger data (MLS state)

- [ ] **6.17** Background message sync:
  - iOS: Background App Refresh for unread count updates
  - Android: WorkManager for periodic sync
  - Sync: fetch unread counts per channel (NOT message content — preserve battery and bandwidth)
  - Badge count: update app icon badge with total unread count
  - Constraint: mobile OS limits background execution — keep sync minimal

- [ ] **6.18** Biometric authentication:
  - Optional: enable in Settings → Security
  - On app open: prompt for Face ID / fingerprint / PIN
  - Protects: app access and key access
  - Timeout: configurable auto-lock (1min, 5min, 15min, never)
  - Implementation: `expo-local-authentication`

- [ ] **6.19** Offline message cache:
  - SQLite local database (expo-sqlite) for message cache
  - Cache recent messages per channel (last 100)
  - On network loss: display cached messages, queue outbound messages
  - On reconnect: sync — send queued messages, fetch missed messages
  - Clear cache: Settings → Storage → Clear Cache

### Security Hardening

- [ ] **6.20** Threat model document (`docs/security/threat-model.md`):
  - Trust boundaries: client ↔ server, server ↔ SFU, server ↔ federation, server ↔ database
  - Attack surfaces: auth endpoints, WebSocket, federation inbox, file upload, voice signaling
  - Threat actors: malicious users, compromised nodes, network attackers, compromised server
  - Mitigations: per-surface, mapped to implementation
  - Assumptions: server operator is trusted for metadata (but not message content), remote nodes are partially trusted

- [ ] **6.21** API rate limiting:
  - Use `Hammer` library or custom `Plug` with ETS backend
  - Aggressive on auth endpoints: 5 attempts per minute per IP for login, 3 per hour for registration
  - General API: 100 requests per minute per user
  - File upload: 10 uploads per minute per user
  - WebSocket: already rate-limited in Phase 1 (task 1.24)
  - Return `429 Too Many Requests` with `Retry-After` header

- [ ] **6.22** Security headers:
  - CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' wss:`
  - HSTS: `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`
  - Implemented as a Plug in the Phoenix pipeline

- [ ] **6.23** Audit logging:
  - Events logged: auth (login, logout, failed attempts, 2FA changes), role changes, federation handshakes, defederation, server settings changes, moderation actions
  - Storage: dedicated `audit_logs` table (not mixed with application logs)
  - Fields: `event_type`, `actor_id`, `target_id`, `metadata` (JSONB), `ip_address` (operator's choice — can be disabled), `inserted_at`
  - Access: operator only (not exposed to regular users or moderators)
  - Retention: configurable, default 90 days, auto-pruned via Oban job

- [ ] **6.24** Node signing key rotation:
  - Generate new key pair: `POST /api/v1/admin/federation/rotate-key`
  - Grace period: advertise both old and new key in `/.well-known/federation` for 7 days
  - Notify federated peers of key change via ActivityPub `Update` activity
  - After grace period: remove old key, use only new key
  - Document rotation procedure for operators

- [ ] **6.25** Automated security scanning in CI:
  - Elixir: `sobelow` (static security analysis for Phoenix)
  - Node.js: `npm audit` (dependency vulnerability scan)
  - Rust: `cargo audit` (dependency vulnerability scan)
  - Run on every PR, fail CI on high/critical vulnerabilities
  - Weekly scheduled scan for new vulnerabilities in existing dependencies

- [ ] **6.26** Third-party security audit:
  - Commission professional security audit before public beta
  - Scope: server API, authentication, E2E encryption implementation, federation protocol, WebSocket handling
  - Budget: allocate in advance, audit firms need 4-8 weeks lead time
  - Remediate all critical and high findings before release

- [ ] **6.27** Security disclosure program:
  - `SECURITY.md` in repository root:
    - How to report vulnerabilities (email, encrypted if possible)
    - Response timeline commitment (acknowledge within 48h, triage within 1 week)
    - Safe harbor statement
  - No bug bounty initially (reconsider at scale)

### Deployment

- [ ] **6.28** Official Docker images:
  - Phoenix server: Alpine-based or distroless, multi-stage build (build deps → release)
  - SFU: Node.js Alpine, include mediasoup native dependencies
  - Image size targets: <100MB for server, <200MB for SFU
  - Published to Docker Hub or GitHub Container Registry
  - Tags: `latest`, semver (`v1.0.0`), `main` (latest commit)

- [ ] **6.29** Production Docker Compose (`deploy/docker-compose.prod.yml`):
  - Services: Phoenix, SFU, PostgreSQL, Redis, Meilisearch
  - Configuration via `.env` file (template provided as `.env.example`)
  - Volume mounts: PostgreSQL data, Redis data, file uploads, TLS certificates
  - Resource limits: CPU and memory caps per service
  - Restart policy: `unless-stopped`
  - Health checks for all services

- [ ] **6.30** Ansible playbooks (`deploy/ansible/`):
  - Target: single VPS deployment (minimum $5/month, 1 vCPU, 1GB RAM)
  - Playbooks:
    - `setup.yml` — install Docker, create user, configure firewall (UFW), set up swap
    - `deploy.yml` — pull images, start services, run migrations, verify health
    - `backup.yml` — automated backup (see task 6.32)
    - `update.yml` — pull new images, rolling restart, run migrations, verify
  - Inventory: single host, configurable via `host_vars`

- [ ] **6.31** Disk encryption documentation:
  - LUKS full-disk encryption setup guide for Linux VPS
  - Covers: initial setup, key management, unlock on boot (remote unlock via dropbear SSH)
  - Recommendation: encrypt the data partition at minimum (PostgreSQL data, file uploads, keys)

- [ ] **6.32** Automated backup:
  - Mix task: `mix murmuring.backup`
    - PostgreSQL dump (`pg_dump`, compressed)
    - File storage archive (tar + gzip)
    - Node signing keys (optional, separate encrypted archive)
  - Encrypt backup with operator-provided key (AES-256-GCM)
  - Upload to configurable destination: local path, S3, or rsync to remote
  - Restore documentation: `mix murmuring.restore`
  - Oban scheduled job: daily backup at configurable time

- [ ] **6.33** Prometheus metrics endpoint:
  - `GET /metrics` — Prometheus-compatible text format
  - Metrics:
    - HTTP request count, latency histogram (by endpoint)
    - WebSocket connection count, message throughput
    - Ecto query count, latency histogram
    - Federation: messages sent/received, delivery latency, error count
    - Voice: active rooms, participants, bandwidth
    - System: BEAM VM stats (process count, memory, schedulers)
  - Implementation: `PromEx` or `Telemetry.Metrics` + Prometheus exporter

- [ ] **6.34** Grafana dashboard templates:
  - `deploy/grafana/` — JSON dashboard definitions, importable into Grafana
  - Dashboards:
    - **Overview:** request rate, error rate, response time p50/p95/p99, active users, WebSocket connections
    - **Federation:** messages in/out per node, delivery queue depth, error rate, latency
    - **Voice:** active voice channels, participants, bandwidth utilization
    - **Database:** query rate, slow queries, connection pool usage
    - **System:** CPU, memory, disk, BEAM VM health

- [ ] **6.35** Structured logging with correlation IDs:
  - Each HTTP request assigned a correlation ID (UUID, `X-Request-ID` header)
  - Correlation ID propagated to: Ecto queries, Oban jobs, WebSocket handlers, federation deliveries
  - Log format includes correlation ID for distributed tracing
  - External log aggregation: document setup with Loki, ELK, or hosted services

### Distribution — Server

> The server install experience is critical. A solo community operator should be able to go from zero to running instance in one command. Advanced users who want to customize should be able to skip the wizard and configure manually.

- [ ] **6.36** Interactive install script (`install.sh`):
  - One-command install:
    ```bash
    curl -sSL https://get.murmuring.dev/install | sh
    ```
  - The script itself is hosted in the repo (`deploy/install.sh`) and mirrored to the project domain
  - Script prerequisites check: Docker, Docker Compose, available ports (80, 443, 5432), disk space, OS compatibility (Linux — Debian/Ubuntu/Fedora/Arch, macOS for local dev)
  - If prerequisites are missing, offer to install them (with user confirmation) or exit with clear instructions

- [ ] **6.37** Install wizard (interactive mode):
  - Runs by default when the script detects a TTY
  - Step-by-step prompts:
    1. **Domain:** "What domain will this instance run on?" (e.g., `chat.example.com`) — validates format, checks DNS resolution
    2. **TLS:** "Set up automatic HTTPS via Let's Encrypt?" (Y/n) — if yes, prompt for admin email for ACME registration
    3. **Storage:** "Where should files be stored?" — Local filesystem (default path) / S3-compatible (prompt for endpoint, bucket, keys)
    4. **Admin account:** "Create admin username and password" — validates strength
    5. **Federation:** "Enable federation with other Murmuring nodes?" (y/N) — can be enabled later
    6. **Voice:** "Enable voice/video channels?" (Y/n) — if yes, configure TURN (bundled coturn or external)
    7. **Resource limits:** "Expected community size?" — Small (<50 users) / Medium (50-500) / Large (500+) — sets Docker resource limits and PostgreSQL tuning accordingly
  - Writes answers to a `.env` file and a `murmuring.yml` config file
  - Pulls Docker images, starts services, runs migrations, creates admin account
  - Final output: "Your Murmuring instance is running at https://chat.example.com" with next steps

- [ ] **6.38** Advanced / non-interactive install:
  - `install.sh --config /path/to/murmuring.yml` — skip wizard, use pre-written config
  - `install.sh --env /path/to/.env` — skip wizard, use env file
  - Config file reference documentation: every option, defaults, and valid values
  - Headless/CI-friendly: exits cleanly with status codes, machine-readable output with `--json` flag
  - Docker Compose override support: `docker-compose.override.yml` for custom volume mounts, extra services, network config

- [ ] **6.39** Operator CLI tool (`murmuring-ctl`):
  - Bundled in the Docker image, invoked via: `docker exec murmuring murmuring-ctl <command>`
  - Or installed standalone for operators who want it outside Docker
  - Commands:
    - `murmuring-ctl status` — service health, version, uptime, connected users
    - `murmuring-ctl upgrade` — pull latest images, run migrations, restart (with confirmation)
    - `murmuring-ctl backup` — trigger backup (wraps `mix murmuring.backup`)
    - `murmuring-ctl restore <file>` — restore from backup
    - `murmuring-ctl federation list` — show federated nodes
    - `murmuring-ctl federation add <url>` — add federated node
    - `murmuring-ctl user create <username>` — create user (interactive password prompt)
    - `murmuring-ctl user reset-password <username>` — reset password
    - `murmuring-ctl config set <key> <value>` — change runtime config
    - `murmuring-ctl logs` — tail structured logs with filtering
  - Implemented as a Mix task suite (`mix murmuring.*`) with a shell wrapper for Docker exec

- [ ] **6.40** Package manager distribution (server):
  - **Homebrew tap** (macOS/Linux): `brew install murmuring/tap/murmuring` — installs `murmuring-ctl` + pulls Docker images
  - **AUR** (Arch Linux): PKGBUILD for `murmuring` that installs Docker Compose config + systemd service + `murmuring-ctl`
  - **Nix flake**: `nix run github:murmuring/murmuring` — NixOS module for declarative config
  - **apt/deb repo** (Debian/Ubuntu): `.deb` package that installs systemd service + Docker Compose config
  - All package manager installs ultimately use Docker under the hood — the packages provide the orchestration layer and `murmuring-ctl`

- [ ] **6.41** Upgrade path:
  - `murmuring-ctl upgrade` or re-running the install script detects existing installation
  - Pre-upgrade: automatic backup, version compatibility check
  - Migrations run automatically on startup (Ecto migrations are idempotent)
  - Rollback: `murmuring-ctl rollback` — revert to previous Docker image tags + restore pre-upgrade backup
  - Release notes fetched and displayed before upgrade confirmation
  - Changelog: `CHANGELOG.md` in repo, linked from upgrade output

### Distribution — Web Client

- [ ] **6.42** Web client served by Phoenix:
  - Web client build output (`client/web/dist/`) is embedded into the Phoenix release as static assets
  - Phoenix serves the SPA at `/` with a catch-all route for client-side routing
  - Cache headers: hashed filenames for JS/CSS (`app-abc123.js`) with `Cache-Control: public, max-age=31536000, immutable`
  - `index.html` served with `Cache-Control: no-cache` (so updates propagate immediately)
  - No separate web server (nginx/caddy) needed — Phoenix handles everything
  - Build pipeline: web client built during Docker image build, output copied into Phoenix `priv/static/`

- [ ] **6.43** Web client configuration injection:
  - Server injects runtime config into the SPA at serve time (not build time):
    - Instance name, domain, branding (logo, accent color)
    - Feature flags: federation enabled, voice enabled, registration open/closed
    - Max file upload size, supported file types
  - Mechanism: Phoenix renders a `<script>` tag with `window.__MURMURING_CONFIG__` in `index.html`
  - Client reads config at startup — no rebuild needed when server config changes

### Distribution — Desktop

- [ ] **6.44** Desktop download page:
  - Hosted on project website or as a route on any Murmuring instance (`/download`)
  - Auto-detects OS, highlights correct download button
  - Download links point to GitHub Releases (or self-hosted mirror)
  - Includes: macOS Universal `.dmg`, Windows `.msi` installer, Linux `.AppImage` + `.deb`
  - Checksums (SHA-256) displayed alongside each download

- [ ] **6.45** Desktop package manager distribution:
  - **Homebrew Cask** (macOS): `brew install --cask murmuring`
  - **Winget** (Windows): `winget install Murmuring.Murmuring`
  - **Flathub** (Linux): Flatpak submission for broad distro compatibility
  - **AUR** (Arch Linux): `murmuring-desktop` package
  - **Snap** (Ubuntu): evaluate feasibility (Tauri + Snap sandboxing can conflict)
  - CI pipeline: automate package manager submissions on each release

- [ ] **6.46** Desktop first-run experience:
  - On launch: "Connect to a Murmuring server" → enter server URL (e.g., `chat.example.com`)
  - Server list: remember previously connected servers, switch between them
  - Deep link handling: clicking `murmuring://invite/abc123` opens the app and joins the server
  - If no desktop app installed: invite links fall back to web client with a banner "Get the desktop app"

### Distribution — Mobile

- [ ] **6.47** App Store submission (iOS):
  - Apple Developer account ($99/year)
  - Build via EAS Build, submit via EAS Submit or Transporter
  - App Store metadata: description, screenshots (iPhone + iPad), privacy nutrition labels
  - Privacy nutrition labels must accurately reflect: no data collection (beyond what the chosen server stores), E2E encryption
  - TestFlight for beta testing before public release
  - Review considerations: explain federation model to reviewers (they may not be familiar), emphasize E2E encryption

- [ ] **6.48** Play Store submission (Android):
  - Google Play Developer account ($25 one-time)
  - Build via EAS Build, submit via Play Console
  - Play Store metadata: description, screenshots (phone + tablet), data safety section
  - Data safety section: accurately describe E2E encryption, minimal data collection
  - Internal testing track → Closed beta → Open beta → Production
  - Also publish APK on GitHub Releases for sideloading (F-Droid compatibility — no Google Play Services dependency for core features)

- [ ] **6.49** Mobile server connection:
  - Same as desktop: first launch prompts for server URL
  - QR code scan option: server's web UI can display a QR code with connection details
  - Remember connected servers, switch between multiple servers
  - Push notification token registered per-server

---

## Testing Checkpoint

- [ ] Feature parity across platforms:
  - Web ↔ Desktop ↔ Mobile: same features work on all platforms
  - Auth: login, register, 2FA, recovery codes
  - Messaging: send, receive, edit, delete, react, reply
  - E2E encryption: DMs and private channels work on all platforms
  - Voice: works on all platforms (including Tauri webviews)

- [ ] Key management:
  - Desktop: keys stored in OS keychain, survive app reinstall
  - Mobile: keys stored in secure store, protected by biometrics
  - Key backup/restore works across platforms
  - QR code sync works between web ↔ desktop ↔ mobile

- [ ] Voice across platforms:
  - Desktop (Tauri): test on macOS, Windows, Linux — audio/video functional
  - Mobile: test on iOS + Android physical devices — audio routing works (speaker, earpiece, Bluetooth)
  - E2E voice: Insertable Streams works on platforms that support it, graceful fallback on others

- [ ] Security:
  - Penetration test (professional or self-assessment with OWASP checklist)
  - Rate limiting: verify auth endpoints are protected
  - Security headers: verify with Mozilla Observatory or similar
  - Sobelow/npm audit/cargo audit: no high/critical issues

- [ ] Deployment:
  - Deploy 2 VPS instances using Ansible playbooks
  - Full integration test: federation + encryption + voice across 2 nodes
  - Backup + restore: full round-trip test
  - Monitor via Prometheus + Grafana: verify all metrics flowing

- [ ] Server installation:
  - Fresh VPS (Debian, Ubuntu, Fedora): run install script → complete wizard → instance running with HTTPS
  - Non-interactive install: provide config file → script completes without prompts
  - Upgrade: run `murmuring-ctl upgrade` → new version running, data intact
  - Rollback: `murmuring-ctl rollback` → previous version restored
  - All `murmuring-ctl` commands work as documented

- [ ] Client distribution:
  - Web client served at `/` on any running instance, no separate deployment needed
  - Desktop downloads install and launch on macOS, Windows, Linux
  - Desktop connects to server URL, deep links work (`murmuring://invite/...`)
  - Mobile installs from TestFlight / Play internal track, connects to server, push notifications work
  - Sideloaded APK works without Google Play Services for core features (messaging, encryption)

- [ ] Scalability:
  - MLS with 50+ members: verify performance is acceptable
  - 100+ concurrent WebSocket connections: verify server stability
  - E2E voice latency: acceptable across all platforms

---

## Notes

- This phase is large (8-12 weeks) because it combines four concerns: native clients, security, deployment, and distribution. Consider splitting into sub-phases if needed.
- Desktop (Tauri) is higher priority than mobile. Ship desktop first.
- Mobile push notifications are privacy-sensitive — the push notification service (Apple APNs, Google FCM) can see notification metadata. Never include message content.
- The $5/month VPS target is for a small community (<100 users). Document scaling recommendations for larger deployments.
- Third-party security audit (task 6.26) has a long lead time. Start the engagement process early in this phase.
- React Native + WebRTC on iOS requires careful audio session management. Budget extra testing time for iOS voice.
- The install script is the first thing most operators will interact with. It should be polished, well-tested, and handle edge cases gracefully (partial installs, interrupted runs, re-runs on existing installs).
- The web client is bundled with the server — there is no separate web deployment. This is a deliberate simplification. Operators run one thing and get both the API and the web UI.
- App Store review for encrypted messaging apps can take longer than usual. Submit early, expect reviewer questions about encryption and federation.
- F-Droid compatibility (no Google Play Services) is important for privacy-conscious Android users. Push notifications fall back to polling or self-hosted ntfy when FCM is unavailable.
