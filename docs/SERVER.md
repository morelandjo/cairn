# Server Installation & Setup Guide

## Overview

Cairn is a privacy-first federated communication platform. It provides text messaging with end-to-end encryption (MLS + Double Ratchet), voice and video calls with E2E encryption, file sharing, full-text search, and federation between independent instances.

### Architecture

A Cairn deployment consists of six services:

| Service | Technology | Purpose |
|---------|-----------|---------|
| **server** | Phoenix (Elixir) | Core API, WebSocket, authentication, messaging, federation |
| **sfu** | Fastify (Node.js) + mediasoup | WebRTC selective forwarding unit for voice/video |
| **postgres** | PostgreSQL 16+ | Primary database |
| **redis** | Redis 7+ | Session cache, rate limiting, presence |
| **meilisearch** | Meilisearch 1.12+ | Full-text message search |
| **coturn** | coturn 4+ | TURN/STUN server for NAT traversal |

---

## Prerequisites

- **OS:** Linux (Debian 11+, Ubuntu 20.04+, or Fedora 38+)
- **Docker:** Docker Engine 24+ with Compose v2 plugin
- **Domain:** A publicly resolvable domain name (required for federation; IP address is acceptable when federation is disabled)
- **TLS:** A valid TLS certificate (required for federation; optional for LAN/tunnel deployments — see [TLS Modes](#tls-modes))
- **Ports:** The following must be available:

| Port | Protocol | Service |
|------|----------|---------|
| 80 | TCP | HTTP (for TLS cert issuance) |
| 443 | TCP | HTTPS (reverse proxy) |
| 3478 | TCP/UDP | TURN/STUN |
| 40000-40100 | UDP | WebRTC media (SFU) |
| 49152-49200 | UDP | TURN relay |

Port 4000 (server HTTP) does not need to be publicly exposed if a reverse proxy is used.

### Minimum Recommended Specs

| Scale | vCPU | RAM | Storage | Example |
|-------|------|-----|---------|---------|
| Personal (up to 10 users) | 1 | 1 GB | 20 GB SSD | $4-5/mo VPS (Hetzner CAX11, DigitalOcean Basic) |
| Small (10-100 users) | 2 | 4 GB | 40 GB SSD | $10-15/mo VPS |
| Medium (100-1000) | 4 | 8 GB | 100 GB SSD | $30-50/mo VPS |
| Large (1000+) | 8 | 16 GB | 250 GB SSD + separate DB | Dedicated or multi-node |

The **Personal** tier is designed for close friend groups, families, and small guilds. At this scale, voice/video usage is light (1-3 concurrent calls), Meilisearch can share resources with other services, and a single ARM or x86 vCPU handles the Phoenix server and SFU comfortably. You can also run this tier on a Raspberry Pi 4 (4 GB) or equivalent home server.

---

## Installation

### Option A: Automated Install Script (Recommended)

The install script takes a bare Linux server (Debian, Ubuntu, or Fedora) and sets up everything from scratch — no prerequisites needed other than `curl` and root access.

```bash
curl -sSL https://raw.githubusercontent.com/cairn/cairn/main/deploy/install.sh | sudo bash
```

The script will:

1. **Provision the system** — install Docker + Compose, create a `cairn` system user, configure UFW firewall rules (SSH, HTTP, HTTPS, TURN), set up fail2ban (SSH brute-force protection), and add swap on small servers
2. **Walk you through configuration** — prompt for domain/IP, server port, secrets (auto-generate or provide your own), federation, SSL enforcement, and S3 storage
3. **Deploy Cairn** — write `.env`, download `docker-compose.yml`, pull Docker images, start all services, run database migrations, and verify health

Everything is idempotent — if Docker is already installed, or the firewall is already configured, those steps are skipped. Safe to re-run.

On success:

```
Cairn is running!

URL:     http://your.domain.com:4000
Config:  /opt/cairn/.env
Logs:    cd /opt/cairn && docker compose logs -f
Manage:  cairn-ctl status

Next steps:
1. Set up reverse proxy (nginx/Caddy) with TLS
2. Create admin account
3. Configure federation (if enabled)
```

### Option B: Docker Compose (Manual)

1. Create the deployment directory:

```bash
mkdir -p /opt/cairn && cd /opt/cairn
```

2. Download the production Compose file:

```bash
curl -O https://raw.githubusercontent.com/cairn/cairn/main/deploy/docker-compose.prod.yml
mv docker-compose.prod.yml docker-compose.yml
```

3. Create a `.env` file from the template:

```bash
curl -O https://raw.githubusercontent.com/cairn/cairn/main/deploy/.env.example
cp .env.example .env
chmod 600 .env
```

4. Edit `.env` and fill in required values (see [Configuration Reference](#configuration-reference)):

```bash
# Generate secrets
openssl rand -base64 48  # Use for SECRET_KEY_BASE, JWT_SECRET, MEILI_MASTER_KEY
openssl rand -hex 16     # Use for POSTGRES_PASSWORD, SFU_AUTH_SECRET, TURN_SECRET
```

5. Start services:

```bash
docker compose up -d
```

6. Run database migrations:

```bash
docker compose exec -T server bin/cairn eval "Cairn.Release.migrate()"
```

7. Verify health:

```bash
curl http://localhost:4000/health
```

### Option C: Ansible Deployment

For operators managing multiple servers or preferring infrastructure-as-code, four playbooks are provided in `deploy/ansible/`. These do the same work as the install script but in a repeatable, version-controlled way suitable for fleet management.

| Playbook | Purpose |
|----------|---------|
| `setup.yml` | Provision a fresh VPS (Docker, firewall, fail2ban, swap, cairn user) |
| `deploy.yml` | Deploy Cairn services (Compose, migrations, health check) |
| `backup.yml` | Create full backup (database, uploads, keys) with 30-day retention |
| `update.yml` | Rolling update with pre-update backup and zero-downtime restart |

Usage:

```bash
# Initial server setup
ansible-playbook -i inventory.ini deploy/ansible/setup.yml

# Deploy Cairn
ansible-playbook -i inventory.ini deploy/ansible/deploy.yml

# Create backup
ansible-playbook -i inventory.ini deploy/ansible/backup.yml

# Rolling update
ansible-playbook -i inventory.ini deploy/ansible/update.yml
```

The `setup.yml` playbook configures UFW firewall rules (SSH, HTTP, HTTPS, TURN) and fail2ban SSH protection automatically.

### Option D: Building from Source

Requirements:
- Erlang 28+ and Elixir 1.19+ (manage with [mise](https://mise.jdx.dev))
- Node.js 24+
- PostgreSQL 16+, Redis 7+, Meilisearch 1.12+

```bash
# Clone the repository
git clone https://github.com/cairn/cairn.git
cd cairn

# Install runtimes (if using mise)
mise install

# Server
cd server
mix deps.get
mix ecto.create && mix ecto.migrate
mix phx.server

# SFU (in another terminal)
cd sfu
npm ci
npm run build
npm start

# Web client (in another terminal)
cd client/web
npm ci
npm run dev
```

---

## Configuration Reference

All configuration is via environment variables. Set them in `/opt/cairn/.env` for Docker deployments, or export them for source builds.

### Core

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CAIRN_DOMAIN` | Yes | — | Public domain (e.g., `cairn.example.com`) |
| `SECRET_KEY_BASE` | Yes | — | Phoenix session secret. Generate: `openssl rand -base64 48` |
| `JWT_SECRET` | Yes | — | JWT signing secret. Generate: `openssl rand -base64 48` |
| `SERVER_PORT` | No | `4000` | HTTP port for the server |
| `FORCE_SSL` | No | `true` | Set to `false` to allow HTTP (only safe on private networks, requires federation disabled) |
| `PHX_HOST` | No | `$CAIRN_DOMAIN` | Hostname for URL generation |
| `PHX_SERVER` | No | `true` | Enable HTTP server (always true in Docker) |

### Database

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Prod | — | Ecto URL (e.g., `ecto://cairn:pass@postgres:5432/cairn`) |
| `POSTGRES_PASSWORD` | Yes | — | PostgreSQL password for the `cairn` user |
| `POOL_SIZE` | No | `10` | Database connection pool size |
| `ECTO_IPV6` | No | `false` | Set `true` to connect to PostgreSQL over IPv6 |

### Redis

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REDIS_URL` | No | `redis://redis:6379/0` | Redis connection URL |

### Authentication

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `JWT_SECRET` | Yes | — | JWT signing secret (same as Core section) |

### Federation

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `FEDERATION_ENABLED` | No | `false` | Set `true` to enable federation |
| `CAIRN_DOMAIN` | If federated | — | Domain used in ActivityPub actor URIs |
| `NODE_KEY_PATH` | No | `/app/priv/keys/node_ed25519.key` | Path to Ed25519 node identity key |

### Voice & TURN

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SFU_URL` | No | `http://sfu:4001` | Internal URL to the SFU service |
| `SFU_AUTH_SECRET` | Yes | — | Shared secret for server-SFU auth |
| `TURN_SECRET` | Yes | — | HMAC shared secret for TURN credentials |
| `TURN_URLS` | No | `turn:${CAIRN_DOMAIN}:3478` | TURN server URLs (comma-separated) |
| `RTC_MIN_PORT` | No | `40000` | Minimum UDP port for WebRTC media |
| `RTC_MAX_PORT` | No | `40100` | Maximum UDP port for WebRTC media |
| `ANNOUNCED_IP` | No | `$CAIRN_DOMAIN` | Public IP/hostname for SFU media |

### Storage

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STORAGE_BACKEND` | No | `local` | `local` (filesystem) or `s3` |
| `S3_BUCKET` | If S3 | `cairn-uploads` | S3 bucket name |
| `S3_ENDPOINT` | If S3 | — | S3 endpoint URL |
| `AWS_REGION` | If S3 | `us-east-1` | AWS region |
| `AWS_ACCESS_KEY_ID` | If S3 | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | If S3 | — | AWS secret key |

### Search

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MEILI_URL` | No | `http://meilisearch:7700` | Meilisearch URL |
| `MEILI_MASTER_KEY` | Yes | — | Meilisearch master key |

### Docker Images

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CAIRN_IMAGE` | No | `cairn/server:latest` | Server Docker image |
| `SFU_IMAGE` | No | `cairn/sfu:latest` | SFU Docker image |

---

## Docker Images

Both images use multi-stage Alpine-based builds:

**Server image** (`server/Dockerfile`):
- Build stage: `elixir:1.19-otp-28-alpine` — compiles Mix release
- Runtime: `alpine:3.21` — runs as non-root `cairn` user
- Exposes port 4000, healthcheck on `/health`
- Entrypoint: `bin/cairn start`

**SFU image** (`sfu/Dockerfile`):
- Build stage: `node:24-alpine` — compiles TypeScript, prunes dev deps
- Runtime: `node:24-alpine` — runs as non-root `cairn` user
- Exposes port 4001, healthcheck on `/health`
- Entrypoint: `node dist/index.js`

---

## Production Services

The `docker-compose.prod.yml` defines resource limits for each service:

| Service | Memory Limit | CPU Limit | Restart Policy |
|---------|-------------|-----------|----------------|
| server | 512 MB | 1.0 | unless-stopped |
| sfu | 256 MB | 1.0 | unless-stopped |
| postgres | 256 MB | — | unless-stopped |
| redis | 128 MB | — | unless-stopped |
| meilisearch | 256 MB | — | unless-stopped |
| coturn | — | — | unless-stopped |

### Volumes

| Volume | Path in Container | Purpose |
|--------|-------------------|---------|
| `pgdata` | `/var/lib/postgresql/data` | PostgreSQL data |
| `redisdata` | `/data` | Redis persistence (AOF) |
| `meilidata` | `/meili_data` | Search indexes |
| `uploads` | `/app/priv/uploads` | User file uploads |
| `keys` | `/app/priv/keys` | Federation Ed25519 keys |
| `exports` | `/app/priv/exports` | GDPR data exports |

---

## Federation

If you chose to enable federation during the install wizard (or set `FEDERATION_ENABLED=true` in your `.env`), federation is already active — no extra steps required. The server automatically:

- Generates an Ed25519 node identity key on first start (stored at `NODE_KEY_PATH`)
- Serves the well-known discovery endpoints (`/.well-known/cairn`, `/.well-known/webfinger`, `/.well-known/did/:did`)
- Signs outbound requests with HTTP Signatures (RFC 9421)
- Delivers activities asynchronously via ActivityPub with exponential backoff
- Verifies inbound `did:cairn` operation chains for anti-impersonation

### Enabling federation on an existing instance

If you initially installed without federation and want to enable it later:

```bash
cairn-ctl config FEDERATION_ENABLED true
cairn-ctl config CAIRN_DOMAIN your.domain.com
cairn-ctl restart
```

Federation requires TLS — if `FORCE_SSL` was set to `false`, the server will automatically re-enable SSL enforcement.

### Verifying federation

```bash
# Check that well-known endpoints are reachable
curl https://your.domain.com/.well-known/cairn

# List known federation nodes
cairn-ctl federation list
```

### How it works

- **Node identity:** Each instance has an Ed25519 key pair for signing HTTP requests and issuing federated auth tokens.
- **Portable identity:** Users have `did:cairn` self-certifying identifiers. Users on remote instances can join your servers without creating a local account — their home instance issues a signed token, and your server verifies it.
- **Cross-instance DMs:** Users can DM users on other instances. The DM channel lives on the initiator's instance only — messages are never replicated via federation.

See the [Administration Guide](ADMINISTRATION.md#federation-admin) for key rotation, node blocking, and activity monitoring.

---

## TLS Modes

Cairn supports three deployment modes for TLS:

### Mode 1: Domain + Reverse Proxy + TLS (Recommended)

The standard production setup. A reverse proxy (nginx, Caddy) terminates TLS and forwards to the server on port 4000. SSL enforcement is enabled (`FORCE_SSL=true`, the default), so any direct HTTP requests are redirected to HTTPS.

**Requirements:** Domain name, TLS certificate (Let's Encrypt recommended)
**Federation:** Supported

### Mode 2: IP + Tunnel (Tailscale, Cloudflare Tunnel)

The server runs behind a VPN or tunnel that provides transport encryption. SSL enforcement can remain enabled or disabled depending on whether the tunnel terminates TLS before or at the server.

**Requirements:** IP address or domain, tunnel/VPN providing transport security
**Federation:** Supported (if the tunnel provides a stable, publicly reachable HTTPS endpoint)

### Mode 3: IP + No SSL (LAN Only)

For home networks, Raspberry Pi setups, or development. SSL enforcement is disabled (`FORCE_SSL=false`). Clients will show a security warning when connecting.

**Requirements:** IP address
**Federation:** Not supported (federation requires TLS; the server will re-enable SSL enforcement if both are configured)

To disable SSL enforcement, set in your `.env`:

```env
FORCE_SSL=false
```

Clients connecting to an HTTP server will see a warning dialog explaining the risk before proceeding.

---

## TLS & Reverse Proxy

The Cairn server listens on HTTP (port 4000). Use a reverse proxy for TLS termination.

### nginx

```nginx
upstream cairn {
    server 127.0.0.1:4000;
}

server {
    listen 443 ssl http2;
    server_name your.domain.com;

    ssl_certificate /etc/letsencrypt/live/your.domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your.domain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Proxy
    location / {
        proxy_pass http://cairn;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket support
    location /socket {
        proxy_pass http://cairn;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # File uploads
    client_max_body_size 50M;
}

server {
    listen 80;
    server_name your.domain.com;
    return 301 https://$server_name$request_uri;
}
```

### Caddy

```
your.domain.com {
    reverse_proxy localhost:4000
}
```

Caddy handles TLS automatically via Let's Encrypt.

---

## Upgrades

### Using cairn-ctl

```bash
cairn-ctl upgrade
```

This command:
1. Creates a pre-upgrade backup (database, uploads, keys)
2. Pulls the latest Docker images
3. Performs a rolling restart of the server (keeps database running)
4. Waits for the health check to pass
5. Runs database migrations
6. Restarts the SFU

### Using Ansible

```bash
ansible-playbook -i inventory.ini deploy/ansible/update.yml
```

### Manual upgrade

```bash
cd /opt/cairn

# Backup first
cairn-ctl backup

# Pull and restart
docker compose pull
docker compose up -d --no-deps server
docker compose exec -T server bin/cairn eval "Cairn.Release.migrate()"
docker compose up -d --no-deps sfu
```

### Rollback

If an upgrade fails:

```bash
cairn-ctl rollback
```

This restores the database from the most recent backup and restarts all services.

---

## Directory Structure

A production deployment at `/opt/cairn`:

```
/opt/cairn/
├── .env                    # Configuration (mode 600)
├── docker-compose.yml      # Service definitions
└── backups/
    └── cairn-backup-YYYYMMDD-HHMMSS/
        ├── database.pgdump       # PostgreSQL dump
        ├── uploads.tar.gz        # User file uploads
        └── keys.tar.gz           # Federation keys
```

---

## Troubleshooting

### Server won't start

Check logs:

```bash
cairn-ctl logs server
```

Common causes:
- **Missing env vars:** Ensure all required variables are set in `.env`
- **Port conflict:** Check that port 4000 is free (`ss -tlnp | grep 4000`)
- **Database not ready:** PostgreSQL must be healthy before the server starts

### Database connection errors

```bash
# Check PostgreSQL health
docker compose exec postgres pg_isready -U cairn

# Check connection URL
docker compose exec server bin/cairn eval "IO.inspect(System.get_env(\"DATABASE_URL\"))"
```

### Federation not working

1. Verify federation is enabled: `FEDERATION_ENABLED=true`
2. Check that `CAIRN_DOMAIN` is set and publicly resolvable
3. Test well-known endpoint: `curl https://your.domain.com/.well-known/cairn`
4. Check federation logs: `cairn-ctl logs server | grep federation`

### Voice/video issues

1. Verify TURN is accessible: `curl http://your.domain.com:3478`
2. Check SFU health: `docker compose exec sfu curl http://localhost:4001/health`
3. Ensure UDP ports 40000-40100 and 49152-49200 are open in your firewall
4. Verify `ANNOUNCED_IP` matches your server's public IP or domain

### Health check failing

```bash
# Direct health check
curl -v http://localhost:4000/health

# Check all service health
docker compose ps
```

The `/health` endpoint returns HTTP 200 when the server is ready.

### Disk space

```bash
# Check Docker volume usage
docker system df -v

# Clean unused images
docker image prune -a
```
