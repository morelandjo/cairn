# Phase 3: Server/Guild Foundation

**Status:** Complete
**Goal:** Add the Server/Guild entity (Discord-style "servers" that own channels, roles, and members), restructure the flat channel model into a server-scoped hierarchy, and build a Discord-like server selector in the web client.
**Dependencies:** Phase 2 complete (MLS encryption, private channels, key backup, web client with 99 server tests).
**Deliverable:** Users can create servers, manage roles and permissions, invite members, and navigate between servers in the client. DMs remain server-less. All pre-existing data migrated to a default server.

---

## What Changed

The protocol spec (Section 3.2) defines a `MurmuringServer` entity — a Discord-style server/guild that owns channels, roles, and members. Before Phase 3, channels were flat top-level entities with no parent container. This phase introduced the server hierarchy and restructured everything around it.

---

## Database Changes

### Migration: `20260210164827_create_servers_and_add_server_id.exs`

Created two new tables and added foreign keys to existing tables:

- **`servers`** table: `id` (UUID), `name` (string 100), `description` (text), `icon_key` (string, nullable), `creator_id` (FK users), timestamps
- **`server_members`** table: `id` (UUID), `server_id` (FK servers), `user_id` (FK users), `role_id` (FK roles, nullable), timestamps. Unique index on `[server_id, user_id]`
- Added nullable `server_id` FK to `channels`, `roles`, `invite_links`
- Dropped `unique_index(:roles, [:name])`, created `unique_index(:roles, [:server_id, :name])` (roles are now per-server)

### Migration: `20260210164828_backfill_default_server.exs`

Data migration that preserves all existing data:

1. Creates a "Default Server" owned by the first user
2. Backfills `server_id` on all non-DM channels, roles, and invite links
3. Creates `server_members` entries for all existing channel members
4. Creates default roles: @everyone (priority 0), Moderator (50), Admin (90), Owner (100)
5. Adds CHECK constraint: `(type='dm' AND server_id IS NULL) OR (type!='dm' AND server_id IS NOT NULL)`

Used raw SQL with `Ecto.UUID.dump/1` for binary UUID encoding in the data migration.

---

## Server Modules

### `Murmuring.Servers` (context)

CRUD operations for servers with automatic setup:

- `create_server/1` — creates server, auto-generates 4 default roles (@everyone, Moderator, Admin, Owner), adds creator as Owner member
- `list_user_servers/1` — returns all servers a user belongs to
- `get_server/1`, `update_server/2`, `delete_server/1`
- `add_member/2`, `remove_member/2`, `is_member?/2`, `list_members/1`
- `create_role/1`, `update_role/2`, `delete_role/1`, `list_server_roles/1`
- `assign_role/3`, `unassign_role/2`

### `Murmuring.Servers.Server` (schema)

Fields: `name`, `description`, `icon_key`, `creator_id`. Has many channels, roles, server_members.

### `Murmuring.Servers.ServerMember` (schema)

Fields: `server_id`, `user_id`, `role_id`. Belongs to server, user, role.

---

## Per-Server Roles & Permissions

### `Murmuring.Servers.Permissions`

15 protocol-defined permission keys:

| Permission | Description |
|---|---|
| `send_messages` | Send messages in channels |
| `read_messages` | Read messages in channels |
| `manage_messages` | Edit/delete others' messages |
| `manage_channels` | Create/edit/delete channels |
| `manage_roles` | Create/edit/delete roles |
| `manage_server` | Edit server settings |
| `kick_members` | Kick members from server |
| `ban_members` | Ban members from server |
| `invite_members` | Create invite links |
| `manage_webhooks` | Manage webhooks |
| `attach_files` | Upload files |
| `use_voice` | Join voice channels |
| `mute_members` | Mute members in voice |
| `deafen_members` | Deafen members in voice |
| `move_members` | Move members between voice channels |

Resolution logic:
- `has_permission?(server_id, user_id, permission)` — fetches user's roles, checks permission
- `effective_permissions(server_id, user_id)` — returns full permission map
- **Server creator always bypasses all permission checks**
- @everyone role (priority 0) is always included as base permissions
- Additive: permissions OR'd across all assigned roles

### `MurmuringWeb.Plugs.ServerAuth`

Plug that extracts server from route/channel, calls `Permissions.has_permission?/3`, returns 403 on denial. DMs bypass permission checks entirely.

Applied to:
- Channel create → `manage_channels`
- Message read/show → `read_messages`
- Invite create → `invite_members`
- WebSocket `new_msg` → `send_messages`
- Manage others' messages → `manage_messages`

---

## Channel & Invite Refactor

### `Murmuring.Chat.Channel` (modified)

- Added `belongs_to :server` association
- Validation: `server_id` required for non-DM channels, NULL for DMs
- CHECK constraint enforced at DB level

### `Murmuring.Chat` (modified)

New server-scoped queries:
- `list_server_channels(server_id)` — all channels in a server
- `list_user_server_channels(server_id, user_id)` — channels visible to user in a server
- `create_channel/1` — now requires `server_id` for non-DM channels
- `create_server_invite/1` — server-level invites (channel_id=nil)

### `Murmuring.Accounts.InviteLink` (modified)

- Added optional `server_id` field
- Server-level invites: `server_id` set, `channel_id` nil
- Server invite usage → adds user to server with @everyone role

### `Murmuring.Accounts.Role` (modified)

- Added `belongs_to :server` association
- `server_id` required on all roles
- Unique index changed to `[server_id, name]` (two servers can each have "Moderator")

---

## Server API Endpoints

### `MurmuringWeb.ServerController`

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/servers` | List user's servers |
| POST | `/api/v1/servers` | Create server |
| GET | `/api/v1/servers/:id` | Show server |
| PUT | `/api/v1/servers/:id` | Update server |
| DELETE | `/api/v1/servers/:id` | Delete server |
| GET | `/api/v1/servers/:id/members` | List members |
| GET | `/api/v1/servers/:id/channels` | List channels |
| POST | `/api/v1/servers/:id/channels` | Create channel in server |
| GET | `/api/v1/servers/:id/roles` | List roles |
| POST | `/api/v1/servers/:id/roles` | Create role |
| PUT | `/api/v1/servers/:id/roles/:role_id` | Update role |
| DELETE | `/api/v1/servers/:id/roles/:role_id` | Delete role |
| POST | `/api/v1/servers/:id/join` | Join server |
| POST | `/api/v1/servers/:id/leave` | Leave server |

---

## Web Client Changes

### New Files

- **`stores/serverStore.ts`** — Zustand store: servers list, `currentServerId`, `fetchServers`, `selectServer`, `createServer`
- **`api/servers.ts`** — Server API client (fetch, create, list channels/members/roles)
- **`components/ServerSidebar.tsx`** — Discord-style vertical icon rail with server first-letter avatars, DM home icon at top, "+" create server button, create modal

### Modified Files

- **`components/ChannelSidebar.tsx`** — Now shows only channels for selected server, displays server name in header
- **`layouts/MainLayout.tsx`** — Added ServerSidebar as first column: `[ServerSidebar 60px | ChannelSidebar 240px | Content | Members]`
- **`App.tsx`** — Server-scoped routes: `/servers/:serverId/channels/:channelId`
- **`App.css`** — ~170 lines added for server sidebar styling (`.server-sidebar`, `.server-icon`, `.server-separator`, `.server-create-modal`, etc.)

### Proto Types Added

```typescript
interface Server { id, name, description?, icon_key?, creator_id, inserted_at }
interface ServerMember { id, username, display_name?, role_id?, role_name? }
interface ServerRole { id, name, permissions, priority, color? }
type PermissionKey = "send_messages" | "read_messages" | ... (15 total)
```

---

## Test Coverage

| Test File | Tests | Description |
|---|---|---|
| `test/murmuring/servers_test.exs` | 16 | Server CRUD, membership, role management |
| `test/murmuring/servers/permissions_test.exs` | 8 | Permission resolution, creator bypass, @everyone base |
| `test/murmuring_web/controllers/server_controller_test.exs` | 14 | All REST endpoints, auth, permission enforcement |

All existing tests continued to pass (channels updated to include `server_id` in 4 test files).

**Final count after Phase 3:** 137 server tests, 0 failures.

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Migration strategy | Default Server + backfill | Zero-downtime, existing data stays valid |
| DM channels | `server_id = NULL` with CHECK | Protocol spec: DMs are server-less |
| Role architecture | Per-server via `server_id` FK | Protocol spec Section 3.5: role context = parent server |
| Membership model | Server → Channel hierarchy | Discord model, server membership is prerequisite |
| Permission resolution | Additive OR, creator bypass | Matches protocol spec |
| API nesting | `/servers/:id/channels` + keep `/channels/:id` | Gradual migration, backward compat |
