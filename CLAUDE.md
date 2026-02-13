# Cairn — Project Instructions

## Repository Layout

- `server/` — Phoenix/Elixir backend
- `sfu/` — Fastify/TypeScript SFU (mediasoup)
- `proto/` — Shared types, API client, MLS WASM
- `client/web/` — React/Vite web frontend
- `client/desktop/` — Tauri v2 desktop shell
- `client/mobile/` — Expo/React Native mobile app
- `deploy/` — Docker Compose, Ansible, install scripts

## Git Remotes

| Remote   | URL                                          | Purpose |
|----------|----------------------------------------------|---------|
| `origin` | `https://github.com/morelandjo/murmuring.git` | Private repo — full development history |
| `public` | `https://github.com/morelandjo/cairn.git`     | Public repo — clean squashed commits only |

## Pushing Code

### Push to private (origin)

Standard push — full history is fine here:

```sh
git push origin main
```

### Push to public (cairn)

**Never push full history to public.** The development history is messy and should not be viewable. Always squash commits when syncing to public:

```sh
# 1. Fetch latest public state
git fetch public

# 2. Create a temp branch from public/main
git checkout -b temp-public public/main

# 3. Squash merge main onto it (takes all content from main)
git merge --squash main --allow-unrelated-histories

# 4. If there are conflicts, resolve by taking main's version:
git checkout main -- .
git add -A

# 5. Commit with a clean message summarizing the changes
git commit -m "Description of changes"

# 6. Push to public
git push public temp-public:main

# 7. Switch back and clean up
git checkout main
git branch -D temp-public
```

### Push to both (typical workflow)

```sh
# Private — direct push
git push origin main

# Public — squash and push (see steps above)
```

## CI / Builds

CI runs automatically on push to `main` on both repos (`.github/workflows/ci.yml`):
- **Elixir**: compile, format, test, Dialyzer, Sobelow
- **TypeScript**: lint, build, test (matrix: proto, sfu, client/web)
- **Rust**: fmt, clippy, test (mls-wasm crate)
- **Desktop**: cargo check (Tauri)
- **Mobile**: tsc --noEmit, expo lint

### Check CI status

```sh
# Private repo
gh run list --repo morelandjo/murmuring --limit 5

# Public repo
gh run list --repo morelandjo/cairn --limit 5

# Watch a specific run
gh run watch --repo morelandjo/murmuring <run-id>
```

### Release builds (triggered by version tags)

Release workflows run when a `v*` tag is pushed:

```sh
# Tag a release
git tag v0.2.0
git push origin v0.2.0
git push public v0.2.0
```

This triggers:
- **release-desktop.yml** — Tauri builds for macOS (aarch64, x86_64), Linux (appimage, deb), Windows (msi). Creates a GitHub draft release with artifacts.
- **release-server.yml** — Docker images for server + SFU, pushed to `ghcr.io/morelandjo/cairn-{server,sfu}:{version,latest}`.
- **release-mobile.yml** — EAS builds (currently disabled until credentials are configured).

## Dev Environment

- **mise** manages runtimes — see `.tool-versions`
- Docker Compose for services: `docker compose -f deploy/docker-compose.dev.yml up -d`
- Local PG on 5432 conflicts with Docker — Docker PG mapped to **port 5433**
- Local Redis on 6379 conflicts — Docker Redis mapped to **port 6380**
- Meilisearch on port 7700

### Run server tests

```sh
cd server && mix test
```

### Run TypeScript checks

```sh
cd client/web && npx tsc --noEmit   # web
cd client/mobile && npx tsc --noEmit # mobile
cd proto && npm test                  # proto
cd sfu && npm test                    # sfu
```

### Build web client

```sh
cd client/web && npm run build
```
