# Phase 0: Prerequisites & Setup

**Duration:** 2-3 weeks
**Goal:** Establish project infrastructure, development environment, and protocol specification.
**Dependencies:** None — this is the foundation phase.
**Deliverable:** A fully scaffolded monorepo with all tooling, a protocol spec draft, and CI running.

---

## Review Issues Addressed

- **#8 — Monitoring/observability:** Structured logging, `/health` endpoint, Telemetry setup
- **#9 — Message formatting spec:** Defined in protocol specification
- **#14 — Protocol versioning:** Versioning scheme defined in protocol spec

---

## Tasks

### Monorepo Initialization

- [ ] **0.1** Initialize monorepo root with directory structure:
  ```
  cairn/
  ├── server/          # Elixir/Phoenix
  ├── sfu/             # Node.js mediasoup sidecar
  ├── client/
  │   ├── web/         # React SPA
  │   ├── desktop/     # Tauri
  │   └── mobile/      # React Native
  ├── proto/           # Shared protocol defs, crypto utils
  ├── docs/            # Architecture, protocol spec, API reference
  └── deploy/          # Docker, Compose, Ansible
  ```
- [ ] **0.2** Git init, `.gitignore` (comprehensive: `_build/`, `deps/`, `node_modules/`, `.env`, `*.beam`, `target/`, `dist/`), `.editorconfig` (2-space indent for Elixir/JS, 4-space for Rust), license file (choose license)
- [ ] **0.3** Tool version management: `.tool-versions` file (asdf-compatible)
  - Elixir 1.17+
  - Erlang/OTP 27+
  - Node.js 20 LTS
  - Rust stable (latest)
- [ ] **0.4** Docker Compose for local development (`deploy/docker-compose.dev.yml`):
  - PostgreSQL 16+ (port 5432, persistent volume)
  - Redis 7+ (port 6379)
  - Meilisearch (port 7700, development master key)

### Project Scaffolding

- [ ] **0.5** Scaffold Phoenix project:
  ```bash
  cd server/
  mix phx.new server --no-html --no-assets --app cairn
  ```
  Configure for API-only mode, JSON responses, WebSocket support.
- [ ] **0.6** Scaffold Node.js SFU project in `sfu/`:
  - `package.json` with mediasoup dependency
  - TypeScript config
  - Basic Express/Fastify HTTP server for control API
  - Placeholder `index.ts` with health check endpoint
- [ ] **0.7** Scaffold React + Vite + TypeScript in `client/web/`:
  - Vite config with React plugin
  - TypeScript strict mode
  - Dependencies: react, react-dom, react-router-dom
  - Placeholder `App.tsx` with routing shell
- [ ] **0.8** Initialize shared `proto/` package:
  - TypeScript project with `package.json`
  - Dependency: `sodium-plus` (libsodium.js bindings)
  - Export structure for crypto utilities, types, constants
  - Build config targeting both ESM and CJS

### Protocol Specification

> This is the most critical Phase 0 deliverable. All subsequent phases depend on it.

- [ ] **0.9** Write protocol specification draft (`docs/protocol-spec.md`):

  - [ ] **0.9.1** ActivityPub extensions — define custom object types:
    - `CairnServer` — server/guild representation
    - `CairnChannel` — channel with type (public/private/dm), encryption status
    - `CairnMessage` — message with optional encrypted payload
    - `CairnRole` — role with permissions map
    - `CairnReaction` — emoji reaction on message

  - [ ] **0.9.2** Federation handshake protocol:
    - Node discovery via `/.well-known/federation`
    - mTLS certificate exchange
    - Channel subscription model (Follow/Accept)
    - Disconnect/defederation signaling

  - [ ] **0.9.3** Message envelope format:
    - **Included:** message ID, author (username@node), channel ID, content/ciphertext, HLC timestamp, cryptographic signature
    - **Excluded:** IP address, device fingerprint, client version, read receipt status

  - [ ] **0.9.4** E2E encryption contract:
    - Key bundle format (identity key, signed prekey, one-time prekeys)
    - X3DH key agreement parameters
    - Double Ratchet message format
    - MLS group session parameters (ciphersuites, epoch management)
    - Encrypted payload structure (nonce + ciphertext + metadata)

  - [ ] **0.9.5** Privacy manifest schema (JSON):
    ```json
    {
      "version": "1.0",
      "logging": { "ip_addresses": false, "message_content": false },
      "retention": { "messages_days": 365, "files_days": 90 },
      "federation": { "metadata_stripped": true, "read_receipts": false }
    }
    ```

  - [ ] **0.9.6** Protocol versioning scheme:
    - Semantic versioning (major.minor.patch)
    - Version negotiation rules during federation handshake
    - Deprecation policy (minimum 2 minor versions of backwards compatibility)
    - Version field in all federated messages

  - [ ] **0.9.7** Message formatting spec:
    - Markdown subset: `**bold**`, `*italic*`, `~~strikethrough~~`, `` `inline code` ``, code blocks with language hint, `[links](url)`, `> blockquotes`
    - User mentions: `@username` (local), `@username@node` (federated)
    - Channel mentions: `#channel-name`
    - Emoji: Unicode emoji, `:custom_emoji_name:`
    - Sanitization rules: no raw HTML, no script injection vectors

### CI/CD Pipeline

- [ ] **0.10** GitHub Actions CI pipeline (`.github/workflows/ci.yml`):

  - [ ] **0.10.1** Elixir job:
    - `mix deps.get`
    - `mix format --check-formatted`
    - `mix test`
    - `mix dialyzer` (Dialyzer for type checking)
    - Cache: `_build/`, `deps/`, PLT files

  - [ ] **0.10.2** TypeScript job (proto/ + client/web/):
    - `npm ci`
    - ESLint
    - Prettier `--check`
    - Vitest (unit tests)
    - Cache: `node_modules/`

  - [ ] **0.10.3** Rust job (when Rust code exists, Phase 2+):
    - `cargo clippy -- -D warnings`
    - `cargo test`
    - `rustfmt --check`
    - Cache: `target/`

### Observability Foundation

- [ ] **0.11** Structured JSON logging:
  - Configure Elixir Logger with JSON backend (`logger_json` or custom formatter)
  - Log format: `{"timestamp", "level", "message", "module", "request_id", ...}`
  - Correlation ID propagation across request lifecycle

- [ ] **0.12** Health check endpoint:
  - `GET /health` — returns 200 OK with JSON body:
    ```json
    { "status": "ok", "version": "0.1.0", "postgres": "connected", "redis": "connected" }
    ```
  - Check PostgreSQL and Redis connectivity
  - Used by Docker health checks and load balancers

- [ ] **0.13** Phoenix Telemetry setup:
  - Attach telemetry handlers for Phoenix endpoint, Ecto queries, and custom events
  - Log slow queries (>100ms threshold)
  - Foundation for Prometheus metrics export in Phase 6

### Staging Environment

- [ ] **0.14** Two-node Docker Compose config (`deploy/docker-compose.staging.yml`):
  - Two Phoenix instances (node-a, node-b) on separate ports
  - Shared PostgreSQL (separate databases) or two PostgreSQL instances
  - Shared Redis or two Redis instances
  - Used for federation testing starting in Phase 3
  - Documented setup instructions

---

## Testing Checkpoint

- [ ] Monorepo clones cleanly, all tools install via `.tool-versions`
- [ ] `docker compose -f deploy/docker-compose.dev.yml up` starts all services
- [ ] Phoenix server starts and responds on `GET /health`
- [ ] `mix test` passes (even if no tests yet, the runner works)
- [ ] `npm test` in `proto/` and `client/web/` passes
- [ ] CI pipeline runs successfully on push
- [ ] Protocol spec draft is complete and reviewed

---

## Notes

- The protocol spec does not need to be final — it's a living document that will evolve. But it must be draft-complete before Phase 1 implementation begins.
- Desktop (`client/desktop/`) and mobile (`client/mobile/`) are scaffolded as empty directories with placeholder READMEs — they're implemented in Phase 6.
- The staging environment is set up now but not actively used until Phase 3 (federation).
