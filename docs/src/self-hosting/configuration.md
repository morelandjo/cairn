# Configuration

All configuration is stored in `/opt/cairn/.env`. Changes take effect after restarting services:

```sh
cairn-ctl restart
```

You can also view or set individual values with:

```sh
cairn-ctl config                    # show all
cairn-ctl config CAIRN_DOMAIN       # show one
cairn-ctl config CAIRN_DOMAIN x.com # set one
```

## Environment variables

### Required

| Variable | Description | How to generate |
|----------|-------------|-----------------|
| `CAIRN_DOMAIN` | Domain name or IP for this instance | — |
| `SECRET_KEY_BASE` | Phoenix cookie signing key (48+ bytes, base64) | `openssl rand -base64 48` |
| `JWT_SECRET` | JWT signing key (48+ bytes, base64) | `openssl rand -base64 48` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `openssl rand -base64 32` |
| `MEILI_MASTER_KEY` | Meilisearch admin key | `openssl rand -base64 32` |
| `SFU_AUTH_SECRET` | Shared secret between server and SFU | `openssl rand -base64 32` |
| `ALTCHA_HMAC_KEY` | HMAC key for proof-of-work challenges | `openssl rand -base64 32` |
| `TURN_SECRET` | TURN server shared secret | `openssl rand -base64 32` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_PORT` | Host port mapped to the server container | `4000` |
| `FORCE_SSL` | Enforce HTTPS redirects. Cannot be `false` when federation is enabled. | `true` |
| `FEDERATION_ENABLED` | Enable federation with other Cairn instances | `false` |
| `TURN_URLS` | Comma-separated TURN server URLs | `turn:<CAIRN_DOMAIN>:3478` |
| `STORAGE_BACKEND` | File storage backend: `local` or `s3` | `local` |
| `CAIRN_IMAGE` | Custom server Docker image | `ghcr.io/morelandjo/cairn-server:latest` |
| `SFU_IMAGE` | Custom SFU Docker image | `ghcr.io/morelandjo/cairn-sfu:latest` |

### S3 storage

Set `STORAGE_BACKEND=s3` and configure these additional variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `S3_BUCKET` | S3 bucket name | `cairn-uploads` |
| `S3_ENDPOINT` | S3 endpoint URL (use for MinIO, Backblaze B2, etc.) | `https://s3.amazonaws.com` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | AWS access key | — |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | — |

### SSL / TLS

Cairn does not terminate TLS itself — use a reverse proxy (see [Reverse Proxy](reverse-proxy.md)). The `FORCE_SSL` flag controls whether the server issues HTTP-to-HTTPS redirects and sets HSTS headers.

Setting `FORCE_SSL=false` disables these redirects, which is useful when running behind a VPN, Tailscale, or Cloudflare Tunnel where TLS is handled externally. Federation requires SSL and will override this setting to `true`.

### SFU

The SFU (Selective Forwarding Unit) handles voice and video media. It runs with `network_mode: host` to support WebRTC's UDP requirements.

| Variable | Description | Default |
|----------|-------------|---------|
| `SFU_AUTH_SECRET` | Shared auth secret (must match the server's value) | — |
| `ANNOUNCED_IP` | Public IP/domain the SFU advertises to clients | `CAIRN_DOMAIN` |
| `RTC_MIN_PORT` | Start of UDP port range for media | `40000` |
| `RTC_MAX_PORT` | End of UDP port range for media | `40100` |

### Resource limits

The production Docker Compose file sets default memory limits:

| Service | Memory | CPU |
|---------|--------|-----|
| server | 512 MB | 1.0 |
| sfu | 256 MB | 1.0 |
| postgres | 256 MB | — |
| redis | 128 MB | — |
| meilisearch | 256 MB | — |

To adjust these, edit the `deploy` section in your `docker-compose.yml`.
