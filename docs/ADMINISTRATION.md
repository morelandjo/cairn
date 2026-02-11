# Server Administration Guide

## Overview

This guide covers day-to-day administration of a Murmuring instance: user management, moderation, federation, monitoring, and maintenance. For initial installation and setup, see the [Server Installation Guide](SERVER.md).

### Admin Authentication

Admin operations are performed through:

1. **`murmuring-ctl` CLI** — shell commands on the server host
2. **Admin API** — HTTP endpoints under `/api/v1/admin/` requiring an authenticated admin user
3. **Server settings UI** — web client interface for server owners and admins

A user with the **Owner** or **Admin** role on a server can access moderation and management features for that server. Instance-level admin operations (federation, key rotation) require the `manage_server` permission or direct server access via `murmuring-ctl`.

---

## Operator CLI

The `murmuring-ctl` command manages a Murmuring deployment from the server host. It expects the deployment at `/opt/murmuring` by default (override with `MURMURING_DIR` environment variable).

### Commands

#### `murmuring-ctl status`

Shows the status of all Docker Compose services and performs a health check on the server.

```bash
$ murmuring-ctl status
# Shows: docker compose ps output + health check result
```

#### `murmuring-ctl start`

Starts all services.

```bash
$ murmuring-ctl start
# Runs: docker compose up -d
```

#### `murmuring-ctl stop`

Stops all services without removing containers.

```bash
$ murmuring-ctl stop
# Runs: docker compose stop
```

#### `murmuring-ctl restart`

Restarts all services and shows status.

```bash
$ murmuring-ctl restart
```

#### `murmuring-ctl logs [service]`

Tails logs for all services, or a specific service.

```bash
$ murmuring-ctl logs           # All services
$ murmuring-ctl logs server    # Server only
$ murmuring-ctl logs sfu       # SFU only
```

#### `murmuring-ctl upgrade`

Performs a zero-downtime rolling upgrade:

1. Creates a pre-upgrade backup
2. Pulls latest Docker images
3. Restarts the server container (keeps database running)
4. Waits for health check (30 retries, 2s delay)
5. Runs database migrations
6. Restarts the SFU container
7. Shows final status

```bash
$ murmuring-ctl upgrade
```

#### `murmuring-ctl rollback`

Restores the database from the most recent backup and restarts all services.

```bash
$ murmuring-ctl rollback
```

#### `murmuring-ctl backup`

Creates a full backup in `$DEPLOY_DIR/backups/murmuring-backup-YYYYMMDD-HHMMSS/`:

| File | Contents |
|------|----------|
| `database.pgdump` | PostgreSQL custom-format dump |
| `uploads.tar.gz` | User file uploads |
| `keys.tar.gz` | Federation Ed25519 keys (mode 600) |

```bash
$ murmuring-ctl backup
```

#### `murmuring-ctl restore <path>`

Restores a database from a backup directory. Prompts for confirmation. Requires a manual restart afterward.

```bash
$ murmuring-ctl restore /opt/murmuring/backups/murmuring-backup-20260211-143000
$ murmuring-ctl restart
```

#### `murmuring-ctl config [key] [value]`

View or modify configuration:

```bash
$ murmuring-ctl config                    # Show all config
$ murmuring-ctl config MURMURING_DOMAIN   # Show single value
$ murmuring-ctl config MURMURING_DOMAIN new.domain.com  # Update value
```

Changes are written to `.env`. Restart services for changes to take effect.

#### `murmuring-ctl user create <username> <password>`

Creates a new user account via the Elixir release eval.

```bash
$ murmuring-ctl user create alice 'SecureP@ss123'
```

#### `murmuring-ctl federation list`

Lists all known federation nodes and their status.

```bash
$ murmuring-ctl federation list
# Output: domain [status] for each node
```

#### `murmuring-ctl help`

Shows all available commands with usage.

---

## Admin API

### Federation Management

All federation admin endpoints require an authenticated admin user.

#### List Federation Nodes

```
GET /api/v1/admin/federation/nodes
```

Returns: `[{id, domain, node_id, status, protocol_version, inserted_at}]`

#### Register Federation Node

```
POST /api/v1/admin/federation/nodes
```

Body: `{domain, node_id, public_key, inbox_url, protocol_version, privacy_manifest, status}`

#### Get Node Details

```
GET /api/v1/admin/federation/nodes/:id
```

Returns full node details including `public_key`, `inbox_url`, `privacy_manifest`, timestamps.

#### Block/Unblock Node

```
POST /api/v1/admin/federation/nodes/:id/block
POST /api/v1/admin/federation/nodes/:id/unblock
```

Blocking a node prevents all activity delivery to and from that instance.

#### Delete Node

```
DELETE /api/v1/admin/federation/nodes/:id
```

#### List Federation Activities

```
GET /api/v1/admin/federation/activities?limit=50&node_id=...&direction=outbound
```

Returns: `[{id, activity_type, direction, actor_uri, object_uri, status, error, node_domain, inserted_at}]`

#### Rotate Federation Key

```
POST /api/v1/admin/federation/rotate-key
```

Returns: `{ok: true, node_id, public_key, previous_public_key, message}`

The previous key remains valid for a **7-day grace period** to allow remote nodes to update. This action is logged as a `federation.key_rotated` audit event.

---

## User Management

### Creating Users

```bash
murmuring-ctl user create <username> <password>
```

Users can also self-register through the client (rate limited to 3 registrations per hour per IP).

### User Authentication Flow

1. Users register with username + password (8+ character minimum)
2. Registration returns recovery codes (shown once)
3. Users can enable TOTP and/or WebAuthn for 2FA
4. JWT tokens are issued on login (access + refresh tokens)
5. Access tokens are refreshed automatically by clients on 401 responses

### Sessions

Sessions are managed via JWT tokens stored in Redis. When a user changes their password, all existing sessions are invalidated.

### Data Export (GDPR)

Users can request a data export from the client:

```
POST /api/v1/users/me/export          # Initiate export
GET  /api/v1/users/me/export/download  # Download export
POST /api/v1/users/me/export/portability  # Portable format
```

Exports include messages, files, account data, and encryption keys (if backed up). Exports are stored temporarily in the `exports` volume.

---

## Roles & Permissions

### Role Hierarchy

Each server is created with four default roles:

| Role | Priority | Description |
|------|----------|-------------|
| **Owner** | 100 | Server creator. Bypasses all permission checks. |
| **Admin** | 90 | Full management. Can manage channels, roles, bans, webhooks. |
| **Moderator** | 50 | Content moderation. Can manage messages, kick, mute. |
| **@everyone** | 0 | Default role for all members. Basic messaging permissions. |

Custom roles can be created at any priority level.

### Permission Types

| Permission | @everyone | Moderator | Admin | Owner |
|-----------|-----------|-----------|-------|-------|
| `send_messages` | Yes | Yes | Yes | Yes |
| `read_messages` | Yes | Yes | Yes | Yes |
| `manage_messages` | — | Yes | Yes | Yes |
| `manage_channels` | — | — | Yes | Yes |
| `manage_roles` | — | — | Yes | Yes |
| `manage_server` | — | — | Yes | Yes |
| `kick_members` | — | Yes | Yes | Yes |
| `ban_members` | — | — | Yes | Yes |
| `invite_members` | — | — | Yes | Yes |
| `manage_webhooks` | — | — | Yes | Yes |
| `attach_files` | Yes | Yes | Yes | Yes |
| `use_voice` | Yes | Yes | Yes | Yes |
| `mute_members` | — | Yes | Yes | Yes |
| `deafen_members` | — | Yes | Yes | Yes |
| `move_members` | — | Yes | Yes | Yes |

### Permission Resolution

Permissions are resolved in this order (later steps override earlier ones):

1. **Server owner** — bypasses all checks
2. **@everyone role** — base permissions for all members
3. **Assigned roles** — additive OR across all user roles (by priority, low to high)
4. **Channel role overrides** — per-channel grants/denies by role (by priority)
5. **Channel user overrides** — per-channel grants/denies for specific users (highest specificity)

Override values: `grant`, `deny`, or `inherit` (falls through to the next level).

### Multi-Role

Users can have multiple roles simultaneously. Permissions are combined with additive OR — if any role grants a permission, the user has it (unless explicitly denied by a higher-priority override).

### Managing Roles

```
GET    /api/v1/servers/:server_id/roles              # List roles
POST   /api/v1/servers/:server_id/roles              # Create role
PUT    /api/v1/servers/:server_id/roles/:role_id      # Update role
DELETE /api/v1/servers/:server_id/roles/:role_id      # Delete role
POST   /api/v1/servers/:id/members/:uid/roles/:role_id    # Assign role
DELETE /api/v1/servers/:id/members/:uid/roles/:role_id    # Remove role
```

### Channel Permission Overrides

```
PUT    /api/v1/servers/:id/channels/:cid/overrides/role/:role_id   # Set role override
DELETE /api/v1/servers/:id/channels/:cid/overrides/role/:role_id   # Delete role override
PUT    /api/v1/servers/:id/channels/:cid/overrides/user/:user_id   # Set user override
DELETE /api/v1/servers/:id/channels/:cid/overrides/user/:user_id   # Delete user override
GET    /api/v1/servers/:id/channels/:cid/overrides                 # List overrides
```

---

## Moderation

### Muting Users

Mutes prevent a user from sending messages in a server or specific channel. Mutes can have an optional duration.

```
POST   /api/v1/servers/:server_id/mutes       # Mute user
DELETE /api/v1/servers/:server_id/mutes/:user_id  # Unmute
GET    /api/v1/servers/:server_id/mutes        # List active mutes
```

**Mute parameters:**
- `user_id` (required)
- `reason` (optional)
- `duration_seconds` (optional — if set, auto-unmutes after expiry via Oban worker)
- `channel_id` (optional — for channel-specific mutes)

Requires `mute_members` permission.

### Kicking Users

Kicks immediately remove a user from the server. They can rejoin via invite.

```
POST /api/v1/servers/:server_id/kicks/:user_id
```

Requires `kick_members` permission.

### Banning Users

Bans remove a user and prevent them from rejoining. Bans can have an optional duration.

```
POST   /api/v1/servers/:server_id/bans         # Ban user
DELETE /api/v1/servers/:server_id/bans/:user_id # Unban
GET    /api/v1/servers/:server_id/bans          # List active bans
```

**Ban parameters:**
- `user_id` (required)
- `reason` (optional)
- `duration_seconds` (optional — auto-unbans after expiry)

Requires `ban_members` permission.

### Moderation Log

All moderation actions are logged automatically.

```
GET /api/v1/servers/:server_id/moderation-log
```

Returns entries with: `id`, `action`, `details`, `moderator_id`, `moderator_username`, `target_user_id`, `target_username`, `inserted_at`.

**Logged actions:** `mute`, `unmute`, `kick`, `ban`, `unban`, `delete_message`, `pin_message`, `report`, `auto_mod`

Requires `manage_server` permission.

### Reports

Any user can report a message. Moderators can review and resolve reports.

```
POST /api/v1/messages/:message_id/report              # File report (any user)
GET  /api/v1/servers/:server_id/reports               # List reports
PUT  /api/v1/servers/:server_id/reports/:report_id    # Resolve report
```

**Report parameters:**
- `reason` (required)
- `details` (optional)

**Resolution statuses:** `pending`, `dismissed`, `actioned`

Requires `manage_messages` permission to view and resolve.

### Slow Mode

Restrict how often users can send messages in a channel.

```
PUT /api/v1/channels/:id/slow-mode
```

---

## Auto-Moderation

Automated content filtering runs on incoming messages and can take actions without moderator intervention.

### Rule Types

| Type | Description |
|------|-------------|
| `word_filter` | Block messages containing specified words/phrases |
| `regex_filter` | Block messages matching a regular expression pattern |
| `link_filter` | Block messages containing URLs (with optional allow/block lists) |
| `mention_spam` | Block messages with excessive @mentions |

### Managing Rules

```
GET    /api/v1/servers/:server_id/auto-mod-rules            # List rules
POST   /api/v1/servers/:server_id/auto-mod-rules            # Create rule
PUT    /api/v1/servers/:server_id/auto-mod-rules/:rule_id   # Update rule
DELETE /api/v1/servers/:server_id/auto-mod-rules/:rule_id   # Delete rule
```

**Rule parameters:**
- `rule_type` — one of the types above
- `enabled` — boolean toggle
- `config` — type-specific configuration map (word lists, patterns, thresholds)

Requires `manage_server` permission.

Auto-mod actions are logged in the moderation log with action type `auto_mod`.

---

## Rate Limiting

### HTTP Rate Limits

The server enforces per-endpoint rate limits using an ETS-based token bucket. Limits apply per authenticated user ID, or per IP address for unauthenticated requests.

| Endpoint | Rate | Window |
|----------|------|--------|
| `POST /api/v1/auth/login` | 5 requests | 60 seconds |
| `POST /api/v1/auth/register` | 3 requests | 1 hour |
| Other `/api/v1/auth/*` | 20 requests | 60 seconds |
| `POST /api/v1/upload` | 10 requests | 60 seconds |
| All other `/api/v1/*` | 100 requests (burst: 120) | 60 seconds |

When a rate limit is exceeded, the server returns HTTP 429 (Too Many Requests) with a `Retry-After` header indicating when the client can retry.

Rate limit state is stored in the `:http_rate_limiter` ETS table. Stale entries (older than 5 minutes) are cleaned up every minute.

### Configuration

Rate limiting can be disabled entirely (not recommended for production):

```elixir
config :murmuring, :http_rate_limiting, false
```

### Registration Bot Protection

Registration is protected by two additional layers beyond rate limiting:

**ALTCHA Proof-of-Work** — Before registering, the client fetches a cryptographic challenge from `GET /api/v1/auth/challenge` and must brute-force a SHA-256 hash to solve it (~1-2 seconds of CPU time). The solved payload is submitted with the registration request. This makes bulk automated registration computationally expensive. Challenges are HMAC-signed to prevent forgery.

The HMAC key is configured via the `ALTCHA_HMAC_KEY` environment variable (generate with `openssl rand -base64 32`). PoW verification can be disabled in development/test:

```elixir
config :murmuring, :require_pow, false
```

**Honeypot Field** — The registration form includes a hidden `website` field that is invisible to real users but auto-filled by naive bots. Any request with a non-empty `website` field is rejected.

Both mechanisms are privacy-preserving: no third-party services, no user tracking, no cookies.

### SSL Enforcement

SSL enforcement is controlled by the `FORCE_SSL` environment variable (default: `true`). When enabled, the `RequireSsl` plug redirects HTTP requests to HTTPS, and the `SecurityHeaders` plug adds HSTS headers.

```env
# Disable SSL enforcement (only safe on trusted private networks)
FORCE_SSL=false
```

**Constraints:**
- When federation is enabled, SSL enforcement is always on regardless of the `FORCE_SSL` setting. The server logs a warning and overrides the value.
- Localhost and `127.0.0.1` requests are never redirected, even with SSL enforcement enabled.
- The `/health` endpoint is never redirected, so monitoring tools can always reach it over HTTP.
- Clients connecting to an HTTP server see an "Insecure Connection" warning dialog before proceeding.

### DM Request Rate Limits

Cross-instance DM requests have separate rate limits to prevent spam:

| Limit | Default | Description |
|-------|---------|-------------|
| Requests per hour | 10 | Max DM requests a user can send per hour |
| Pending per recipient | 5 | Max pending (unresponded) DM requests per recipient DID |

These limits are enforced in `DmController` and apply per authenticated user (sender) or per recipient DID. Users can also block specific DIDs to prevent future DM requests.

### IP Detection

The rate limiter uses the `X-Forwarded-For` header if present (for reverse proxy setups), falling back to `remote_ip`.

---

## Federation Admin

### Enabling Federation

Set in your `.env`:

```env
FEDERATION_ENABLED=true
MURMURING_DOMAIN=your.domain.com
```

Restart services for changes to take effect.

### How Federation Works

- Each instance has an Ed25519 node identity key for signing requests
- Outbound activities are signed with HTTP Signatures (RFC 9421)
- Activities are delivered asynchronously via Oban with exponential backoff
- The ActivityPub inbox/outbox pattern is used for message exchange
- HLC (Hybrid Logical Clock) timestamps ensure consistent ordering across instances
- Metadata (IP addresses, etc.) is stripped before delivery for privacy
- **Portable identity**: Users have `did:murmuring` self-certifying identifiers with hash-chained operation logs. Users can join remote servers without re-registering via node-signed federated auth tokens.
- **Cross-instance DMs**: Users can DM users on remote instances. The DM channel lives on the initiator's instance only — messages are never replicated. A lightweight "DM hint" notification is delivered via federation so the recipient can accept or reject the request. DM messages themselves are never sent over ActivityPub.

### Well-Known Endpoints

The server automatically serves:

```
GET /.well-known/murmuring    # Instance info
GET /.well-known/nodeinfo     # NodeInfo protocol
GET /.well-known/did/:did     # DID document resolution
```

The DID endpoint resolves `did:murmuring:...` identifiers to W3C DID documents by replaying the user's hash-chained operation log. Remote instances use this to verify user identity and detect impersonation.

### Key Rotation

Rotate the federation signing key:

```bash
# Via API
POST /api/v1/admin/federation/rotate-key

# Via Elixir eval
docker compose exec -T server bin/murmuring eval "Murmuring.Federation.NodeIdentity.rotate_key()"
```

After rotation:
- The new key is used for all outgoing signatures immediately
- The previous key is accepted for **7 days** (grace period) to allow remote instances to update
- A `federation.key_rotated` audit event is logged

### Blocking Instances

Block a remote instance to prevent all activity exchange:

```
POST /api/v1/admin/federation/nodes/:id/block
POST /api/v1/admin/federation/nodes/:id/unblock
```

Blocking logs `federation.node_blocked` / `federation.node_unblocked` audit events.

### Portable Identity (DID)

Each user has a `did:murmuring:...` identifier derived from a hash of their genesis operation. The DID is stable across key rotations.

**User key structure:**
- **Signing key** (Ed25519) — used for E2EE, message signing, daily operations
- **Rotation key** (Ed25519) — used only for DID operations (key rotation, handle changes, deactivation)

**DID operations are stored in the `did_operations` table** as a hash-chained, signed log. Each operation references the SHA-256 hash of the previous operation, making the chain tamper-evident.

**Federated users** are cached in the `federated_users` table (keyed by DID and actor URI). The `federated_members` table tracks which remote users have joined which local servers.

**Federated auth tokens**: When a user wants to join a remote server, their home instance issues a time-limited token signed by the node's Ed25519 key. The token contains the user's DID, username, home instance, and target instance. The remote instance verifies the token signature, checks the DID operation chain, and creates a federated membership.

**Key rotation endpoint:**

```
POST /api/v1/users/me/did/rotate-signing-key
```

Rotates the user's signing key. The rotation is recorded in the DID operation chain. The user's DID stays the same.

---

## Monitoring

### Health Check

```
GET /health
```

Returns HTTP 200 when the server is ready. Use this for load balancer health checks and uptime monitoring.

### Prometheus Metrics

```
GET /metrics
```

Metrics are exposed via PromEx in Prometheus text format.

#### Standard Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `phoenix_endpoint_stop_duration_milliseconds_*` | Histogram | HTTP request latency and rate |
| `beam_vm_memory_total_bytes` | Gauge | Total BEAM VM memory |
| `beam_vm_memory_processes_bytes` | Gauge | Process memory |
| `beam_vm_memory_ets_bytes` | Gauge | ETS table memory |
| `ecto_repo_query_total_time_milliseconds_*` | Histogram | Database query latency |
| `oban_job_stop_duration_milliseconds_*` | Histogram | Background job duration by queue |

#### Custom Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `murmuring_websocket_connections_total` | Gauge | Active WebSocket connections (polled every 5s) |
| `murmuring_federation_nodes_active` | Gauge | Active federation nodes (polled every 5s) |
| `murmuring_messages_sent_total` | Counter | Total messages sent |
| `murmuring_federation_activities_total` | Counter | Federation activities (tags: `direction`, `type`) |
| `murmuring_auth_login_total` | Counter | Login attempts (tags: `result`: success/failure) |
| `murmuring_voice_joins_total` | Counter | Voice channel joins |

### Grafana Dashboard

A pre-built Grafana dashboard is provided at `deploy/grafana/murmuring-overview.json`. Import it into your Grafana instance with a Prometheus datasource.

**Dashboard panels:**

1. HTTP Request Rate
2. HTTP Latency (p95/p50)
3. WebSocket Connections
4. Messages Sent Rate
5. Active Federation Nodes
6. Voice Channel Joins
7. BEAM Memory Usage
8. Database Query Latency (p95/p50)
9. Oban Job Queue (success/failure by queue)
10. Login Attempts (success/failure)

### Structured Logging

The server uses structured logging with the Elixir Logger. All HTTP requests include a **correlation ID** (via the `MurmuringWeb.Plugs.CorrelationId` plug) that is:
- Added to the `x-correlation-id` response header
- Included in Logger metadata for request tracing
- Propagated through async jobs

Filter logs by correlation ID to trace a request across the system:

```bash
murmuring-ctl logs server | grep "correlation_id=abc123"
```

---

## Audit Logging

### Event Types

All significant actions are recorded in the `audit_logs` table.

#### Authentication Events
| Event | Description |
|-------|-------------|
| `auth.login` | Successful login |
| `auth.login_failed` | Failed login attempt |
| `auth.logout` | User logout |
| `auth.register` | New account registration |
| `auth.totp_enabled` | TOTP 2FA enabled |
| `auth.totp_disabled` | TOTP 2FA disabled |
| `auth.webauthn_added` | WebAuthn credential added |
| `auth.password_changed` | Password changed |
| `auth.token_refreshed` | Token refresh |

#### Server Events
| Event | Description |
|-------|-------------|
| `server.created` | Server created |
| `server.updated` | Server settings changed |
| `server.deleted` | Server deleted |
| `server.member_joined` | Member joined server |
| `server.member_left` | Member left server |
| `server.member_kicked` | Member kicked |
| `server.member_banned` | Member banned |

#### Role Events
| Event | Description |
|-------|-------------|
| `role.created` | Role created |
| `role.updated` | Role permissions changed |
| `role.deleted` | Role deleted |
| `role.assigned` | Role assigned to member |
| `role.removed` | Role removed from member |

#### Channel Events
| Event | Description |
|-------|-------------|
| `channel.created` | Channel created |
| `channel.updated` | Channel settings changed |
| `channel.deleted` | Channel deleted |

#### Moderation Events
| Event | Description |
|-------|-------------|
| `moderation.mute` | User muted |
| `moderation.unmute` | User unmuted |
| `moderation.ban` | User banned |
| `moderation.unban` | User unbanned |
| `moderation.kick` | User kicked |
| `moderation.report_created` | Report filed |
| `moderation.report_resolved` | Report resolved |

#### Federation Events
| Event | Description |
|-------|-------------|
| `federation.handshake` | Federation handshake completed |
| `federation.node_blocked` | Node blocked |
| `federation.node_unblocked` | Node unblocked |
| `federation.key_rotated` | Federation key rotated |
| `federation.federated_join` | Remote user joined a local server via federated auth |

#### Identity Events
| Event | Description |
|-------|-------------|
| `identity.did_created` | DID created for user (at registration/key upload) |
| `identity.signing_key_rotated` | User rotated their signing key |
| `identity.rotation_key_rotated` | User rotated their rotation key (via recovery codes) |

#### DM Events
| Event | Description |
|-------|-------------|
| `dm.request_created` | Cross-instance DM request sent |
| `dm.request_accepted` | DM request accepted by recipient |
| `dm.request_rejected` | DM request rejected by recipient |
| `dm.sender_blocked` | Recipient blocked a DM sender's DID |

#### Admin Events
| Event | Description |
|-------|-------------|
| `admin.settings_changed` | Instance settings changed |

### Audit Log Fields

Each audit log entry contains:
- `event_type` — one of the types above
- `actor_id` — user who performed the action
- `target_id` — affected resource identifier
- `target_type` — resource type (e.g., "user", "server", "node")
- `metadata` — additional context (map)
- `ip_address` — client IP (only if IP logging is enabled)
- `inserted_at` — UTC timestamp

### Retention

Audit logs are automatically pruned after **90 days** by an Oban worker running daily. Configure retention:

```elixir
# In runtime.exs or .env
config :murmuring, :audit_retention_days, 90
```

### IP Address Logging

IP logging is disabled by default for privacy. Enable it:

```elixir
config :murmuring, :audit_log_ip, true
```

---

## Security Configuration

### Security Headers

The `SecurityHeaders` plug applies the following headers to all responses:

| Header | Value |
|--------|-------|
| `X-Frame-Options` | `DENY` |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` |
| `X-XSS-Protection` | `0` |
| `Cross-Origin-Opener-Policy` | `same-origin` |

Conditional headers:
- **HSTS:** `Strict-Transport-Security: max-age=31536000; includeSubDomains` (when `force_ssl` is enabled)
- **CSP:** Content-Security-Policy with restrictive defaults

### Default Content Security Policy

```
default-src 'self';
script-src 'self';
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob:;
connect-src 'self' wss:;
font-src 'self';
media-src 'self' blob:;
object-src 'none';
frame-ancestors 'none';
base-uri 'self';
form-action 'self'
```

### CORS

CORS is configured at the Phoenix endpoint level. The default allows same-origin requests only. For cross-origin client deployments, configure allowed origins in the endpoint configuration.

### Security Scanning

The CI pipeline runs:
- **Sobelow** — static security analysis for Elixir/Phoenix
- **npm audit** — dependency vulnerability scanning for Node.js packages
- **cargo audit** — dependency vulnerability scanning for Rust (desktop client)

---

## Backup & Recovery

### Automated Backups

#### Using murmuring-ctl

```bash
murmuring-ctl backup
```

Creates a timestamped backup in `/opt/murmuring/backups/` containing:
- `database.pgdump` — PostgreSQL custom-format dump
- `uploads.tar.gz` — all user-uploaded files
- `keys.tar.gz` — federation Ed25519 keys (restricted permissions)

#### Using Ansible

```bash
ansible-playbook -i inventory.ini deploy/ansible/backup.yml
```

The Ansible playbook includes **automatic 30-day retention** — backups older than 30 days are deleted.

### Restoring from Backup

```bash
murmuring-ctl restore /opt/murmuring/backups/murmuring-backup-20260211-143000
murmuring-ctl restart
```

The restore command:
1. Prompts for confirmation
2. Restores the PostgreSQL database from the dump
3. Requires a manual restart to pick up changes

To restore uploads and keys manually:

```bash
# Restore uploads
docker compose exec -T server tar xzf - -C / < backups/murmuring-backup-YYYYMMDD-HHMMSS/uploads.tar.gz

# Restore federation keys
docker compose exec -T server tar xzf - -C / < backups/murmuring-backup-YYYYMMDD-HHMMSS/keys.tar.gz
```

### Backup Recommendations

- Schedule daily backups via cron:
  ```cron
  0 3 * * * /opt/murmuring/murmuring-ctl backup
  ```
- Copy backups to offsite storage (S3, another server)
- Test restore procedures periodically
- The `murmuring-ctl upgrade` command creates an automatic backup before updating
- Keep federation keys secure — they are the instance's identity

---

## Search Administration

### Meilisearch

Full-text search uses Meilisearch with a `messages` index.

**Index configuration:**
- Primary key: `id`
- Searchable attributes: `content`
- Filterable attributes: `channel_id`, `author_id`
- Sortable attributes: `inserted_at`

The index is created automatically on first use via `Murmuring.Search.ensure_index()`.

### Reindexing

If search results are missing or corrupted, reindex by clearing and recreating the Meilisearch data:

```bash
# Stop Meilisearch
docker compose stop meilisearch

# Remove data volume
docker volume rm murmuring_meilidata

# Restart — index will be recreated
docker compose up -d meilisearch
```

Messages are indexed as they are sent. Historical messages sent before search was enabled will not appear in search results unless manually reindexed.

---

## Storage

### Local Storage

By default, uploads are stored on the local filesystem at `/app/priv/uploads` inside the server container, backed by the `uploads` Docker volume.

### S3 Storage

Configure S3-compatible object storage:

```env
STORAGE_BACKEND=s3
S3_BUCKET=murmuring-uploads
S3_ENDPOINT=https://s3.amazonaws.com
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

The `S3_ENDPOINT` can point to any S3-compatible service (MinIO, DigitalOcean Spaces, Backblaze B2, etc.).

### File Access

```
POST /api/v1/upload              # Upload file
GET  /api/v1/files/:id           # Download file
GET  /api/v1/files/:id/thumbnail # Download thumbnail
```

Upload size limits are controlled by the server and reverse proxy configuration (`client_max_body_size` in nginx).

---

## Bots & Webhooks

### Bot Accounts

Bots are automated accounts that can interact with channels via the API.

#### Creating a Bot

```
POST /api/v1/servers/:server_id/bots
```

Returns: `{bot_account, user, token}`

The bot token is shown **once** on creation — store it securely. The bot username is auto-generated as `bot_<8 hex chars>`.

#### Managing Bots

```
GET    /api/v1/servers/:server_id/bots                    # List bots
DELETE /api/v1/servers/:server_id/bots/:bid                # Delete bot
PUT    /api/v1/servers/:server_id/bots/:bid/channels       # Set allowed channels
POST   /api/v1/servers/:server_id/bots/:bid/regenerate-token  # New token
```

Bots authenticate with their token as a Bearer token. They can be restricted to specific channels via the `allowed_channels` setting.

### Webhooks

Webhooks allow external services to post messages to a channel.

#### Creating a Webhook

```
POST /api/v1/servers/:server_id/webhooks
```

Parameters: `name` (1-100 chars), `channel_id`, optional `avatar_key`.

Returns a webhook with a `token`. The public endpoint for posting is:

```
POST /api/v1/webhooks/:token
```

Body: `{content: "message text"}`

No authentication is required — the token itself is the credential.

#### Managing Webhooks

```
GET    /api/v1/servers/:server_id/webhooks                         # List
DELETE /api/v1/servers/:server_id/webhooks/:wid                     # Delete
POST   /api/v1/servers/:server_id/webhooks/:wid/regenerate-token   # New token
```

---

## Custom Emoji

Server administrators can upload custom emoji for use in messages and reactions.

```
GET    /api/v1/servers/:server_id/emojis              # List emoji
POST   /api/v1/servers/:server_id/emojis              # Upload emoji
DELETE /api/v1/servers/:server_id/emojis/:emoji_id    # Delete emoji
```

---

## Notifications

### Push Notification Registration

Mobile clients register Expo push tokens:

```
POST   /api/v1/users/me/push-tokens         # Register token
DELETE /api/v1/users/me/push-tokens/:token   # Unregister
```

Push notifications are delivered via an Oban worker in the `:push` queue using the Expo Push API.

**Privacy:** Push payloads contain only a notification count — never message content or sender information.

### Notification Preferences

```
GET /api/v1/users/me/notification-preferences
PUT /api/v1/users/me/notification-preferences
```

---

## Server Discovery

### Listing in the Directory

Make a server discoverable in the public directory:

```
POST   /api/v1/servers/:server_id/directory/list     # Add to directory
DELETE /api/v1/servers/:server_id/directory/unlist    # Remove from directory
```

### Browsing the Directory

```
GET /api/v1/directory
```

Returns public servers with name, description, member count, and tags.

---

## Troubleshooting

### Server won't start after upgrade

1. Check logs: `murmuring-ctl logs server`
2. If migration failed, fix the issue and re-run: `docker compose exec -T server bin/murmuring eval "Murmuring.Release.migrate()"`
3. If unfixable, rollback: `murmuring-ctl rollback`

### High memory usage

1. Check BEAM memory: monitor `beam_vm_memory_total_bytes` metric
2. Check PostgreSQL: `docker compose exec postgres psql -U murmuring -c "SELECT pg_size_pretty(pg_database_size('murmuring'))"`
3. Check Redis: `docker compose exec redis redis-cli info memory`
4. Consider increasing container memory limits in `docker-compose.yml`

### Rate limiting too aggressive

Adjust rate limits by modifying the `RateLimiter` plug configuration. The default API limit of 100 requests/minute is appropriate for most deployments. If your instance serves many concurrent users, increase the burst allowance.

### Federation delivery failures

1. Check federation activities: `GET /api/v1/admin/federation/activities?direction=outbound`
2. Look for errors in the Oban job queue
3. Verify the remote instance is reachable and not blocking your node
4. Check that your domain resolves correctly and TLS is valid

### Audit logs filling disk

Audit logs are automatically pruned after 90 days. If disk usage is still high:
1. Reduce retention: set `audit_retention_days` to a lower value
2. Manually prune: `docker compose exec -T server bin/murmuring eval "Murmuring.Audit.prune(30)"`

### Search not returning results

1. Verify Meilisearch is healthy: `curl http://localhost:7700/health`
2. Check the `MEILI_MASTER_KEY` matches between server and Meilisearch
3. Only messages sent after search was configured are indexed
4. Reindex if needed (see [Search Administration](#search-administration))

### Correlation ID tracing

To trace a specific request through the system, find the correlation ID from:
- The `x-correlation-id` response header
- Server logs (grep for `correlation_id=`)

```bash
murmuring-ctl logs server | grep "correlation_id=<id>"
```
