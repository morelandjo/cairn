# Quick Start

Get a Cairn instance running in under 10 minutes.

## Prerequisites

- A Linux server (Debian, Ubuntu, or Fedora — and derivatives like Mint, Pop!_OS)
- Root/sudo access
- 1 GB+ RAM (512 MB minimum; 2 GB swap is added automatically on small servers)
- 2 GB+ free disk space
- A domain name pointed at your server (recommended)

## Install

SSH into your server and run:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash
```

The installer will:

1. Install Docker and Docker Compose (if not already present)
2. Create a `cairn` system user
3. Configure UFW firewall and fail2ban
4. Set up swap on low-memory servers
5. Walk you through an interactive configuration wizard
6. Pull Docker images and start all services
7. Run database migrations and verify health
8. Set up a reverse proxy with TLS (Caddy or nginx)

### What the wizard asks

| Prompt | Description | Default |
|--------|-------------|---------|
| Domain name | Your server's domain or IP address | _(required)_ |
| HTTP port | Port the server listens on | `4000` |
| Auto-generate secrets? | Generate all cryptographic secrets automatically | Yes |
| Enable federation? | Allow communication with other Cairn instances | No |
| Enable SSL enforcement? | Redirect HTTP to HTTPS (required if federation is enabled) | Yes |
| Reverse proxy | Caddy (recommended), Nginx + Let's Encrypt, or None | Caddy |
| Use S3 for file storage? | Store uploads in S3 instead of local disk | No |

### Non-interactive install

You can skip the wizard by providing a pre-filled `.env` file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --env /path/to/.env
```

Or supply a custom Docker Compose file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --config /path/to/docker-compose.yml
```

## Verify

Check that everything is running:

```sh
cairn-ctl status
```

You should see all services (server, sfu, postgres, redis, meilisearch, coturn) listed as running, with health reported as **OK**.

## Create your first user

```sh
cairn-ctl user create <username> <password>
```

## Next steps

1. **Create your first server** — log in and click "Create Server" to set up a community
2. **Connect a client** — open `https://your-domain.com` in a browser, or install the [desktop](../clients/desktop.md) or [mobile](../clients/mobile.md) app
3. **Explore advanced options** — see [Configuration](configuration.md), [Administration](administration.md), or [Federation](federation.md)

## File locations

| Path | Contents |
|------|----------|
| `/opt/cairn/.env` | Configuration (secrets, domain, feature flags) |
| `/opt/cairn/docker-compose.yml` | Docker Compose service definitions |
| `/opt/cairn/backups/` | Backup archives |
| `/opt/cairn/keys/` | Federation signing keys |
