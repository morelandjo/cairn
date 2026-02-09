# Phase 4: Moderation, Roles & Community

**Duration:** 6-8 weeks
**Goal:** Community management tools, bots/webhooks, search, and features that make the platform usable for real communities.
**Dependencies:** Phase 3 complete (federation working). Moderation tools must work across federated nodes.
**Deliverable:** A full-featured community platform with moderation, permissions, search, bots, notifications, and GDPR compliance.

---

## Review Issues Addressed

- **#4 — Bot/webhook system:** Incoming webhooks + bot user accounts
- **#6 — Account portability:** Data export + identity key export for node migration (completing work started in Phase 3)
- **#10 — Notification preferences:** Per-channel preferences, DND, quiet hours
- **#15 — Data export/GDPR:** Full user data export (GDPR Article 20)
- **#16 — Server/channel discovery:** Opt-in public server directory

---

## Tasks

### Permissions System

- [ ] **4.1** Role-based permission flags (JSONB):
  ```
  send_messages, read_messages, manage_messages (delete others'),
  manage_channels (create/edit/delete), manage_roles (create/edit/assign),
  kick_members, ban_members, invite_members,
  manage_webhooks, manage_server (name/icon/settings),
  mention_everyone, attach_files, use_voice
  ```
  Each flag is `true` (granted), `false` (denied), or absent (inherit from lower-priority role).

- [ ] **4.2** Permission evaluation order:
  1. `@everyone` base role (lowest priority, applied to all users)
  2. Additive from assigned roles (higher priority number wins on conflict)
  3. Channel-level overrides (per-role and per-user, can grant or deny)
  - Deny at any level overrides grant
  - Server owner bypasses all permission checks

- [ ] **4.3** Role CRUD endpoints:
  - `POST /api/v1/servers/:id/roles` — create role (requires `manage_roles`)
  - `PUT /api/v1/servers/:id/roles/:role_id` — update role
  - `DELETE /api/v1/servers/:id/roles/:role_id` — delete role
  - `POST /api/v1/servers/:id/members/:user_id/roles/:role_id` — assign role
  - `DELETE /api/v1/servers/:id/members/:user_id/roles/:role_id` — remove role
  - Validation: cannot create roles with higher priority than your own highest role

- [ ] **4.4** Channel permission overrides:
  - `PUT /api/v1/channels/:id/permissions/:role_id` — set role override for channel
  - `PUT /api/v1/channels/:id/permissions/user/:user_id` — set user override for channel
  - Override payload: map of permission flags to `grant` | `deny` | `inherit`

### Moderation Tools

- [ ] **4.5** User muting:
  - `POST /api/v1/servers/:id/members/:user_id/mute` — with optional `duration` (seconds) and `reason`
  - Server-wide mute: user can read but not send messages
  - Per-channel mute: same but scoped to a channel
  - Auto-unmute: Oban job processes expired mutes

- [ ] **4.6** User kicking and banning:
  - `POST /api/v1/servers/:id/members/:user_id/kick` — remove from server, can rejoin
  - `POST /api/v1/servers/:id/bans` — ban user (with optional `duration` and `reason`)
  - `DELETE /api/v1/servers/:id/bans/:user_id` — unban
  - `GET /api/v1/servers/:id/bans` — list bans
  - Federation-aware: ban propagates to block remote user from all server channels

- [ ] **4.7** Moderation log:
  - Every moderation action recorded: `mod_logs` table
  - Fields: `id`, `moderator_id`, `target_id`, `action` (mute/kick/ban/unban/delete_message/etc.), `reason`, `metadata` (JSONB), `inserted_at`
  - `GET /api/v1/servers/:id/mod-logs` — paginated, filterable by action/moderator/target
  - Visible to users with `manage_server` or `manage_messages` permission

- [ ] **4.8** Message reporting:
  - `POST /api/v1/messages/:id/report` — with `reason` (enum: spam, harassment, nsfw, illegal, other) and optional `details`
  - Report queue: `GET /api/v1/servers/:id/reports` — list pending reports
  - Report actions: dismiss, delete message, mute user, ban user
  - Each action logged in moderation log

- [ ] **4.9** Slow mode:
  - Per-channel setting: `PUT /api/v1/channels/:id` with `slow_mode_seconds` (0 = disabled)
  - Server enforces: reject messages if user posted within cooldown window
  - Moderators exempt from slow mode
  - Client UI: countdown timer on message input when in slow mode

- [ ] **4.10** Auto-moderation:
  - Configurable rules: `POST /api/v1/servers/:id/automod/rules`
  - Rule types:
    - Word filter: list of blocked words/phrases (exact match and wildcard)
    - Regex pattern: custom regex patterns
    - Link filter: block links, allowlist specific domains, or block specific domains
    - Mention spam: max mentions per message
  - Actions per rule: `delete` | `warn` | `mute` (with duration) | `flag_for_review`
  - Auto-mod actions logged in moderation log with `automod` as moderator

### Channel Organization

- [ ] **4.11** Channel categories:
  - Ecto schema: `channel_categories` (id, name, position, server_id)
  - Channels belong to optional category (`category_id` FK)
  - Categories have their own permission overrides (inherited by child channels unless channel overrides)
  - `POST/PUT/DELETE /api/v1/servers/:id/categories`

- [ ] **4.12** Channel ordering:
  - `position` integer field on channels and categories
  - `PUT /api/v1/servers/:id/channel-order` — batch update positions
  - Client: drag-and-drop reordering in sidebar

- [ ] **4.13** Channel topics:
  - `topic` field on channels (short text, max 1024 chars)
  - Displayed at top of channel view
  - `PUT /api/v1/channels/:id` — update topic (requires `manage_channels`)

- [ ] **4.14** Pinned messages:
  - `POST /api/v1/channels/:id/pins/:message_id` — pin message (requires `manage_messages`)
  - `DELETE /api/v1/channels/:id/pins/:message_id` — unpin
  - `GET /api/v1/channels/:id/pins` — list pinned messages
  - Client: pin icon on message, dedicated "Pinned Messages" panel
  - Max 50 pinned messages per channel

### Message Features

- [ ] **4.15** Message threads (replies):
  - `reply_to_id` field on messages (FK to parent message)
  - Replies displayed inline with "Replying to [username]" context
  - Thread view: click reply chain → expanded thread view in side panel
  - Notifications: thread participants notified of new replies

- [ ] **4.16** Reactions:
  - Ecto schema: `reactions` (message_id, user_id, emoji — Unicode string)
  - `PUT /api/v1/messages/:id/reactions/:emoji` — add reaction
  - `DELETE /api/v1/messages/:id/reactions/:emoji` — remove reaction
  - WebSocket events: `reaction_added`, `reaction_removed`
  - Client: emoji picker, reaction bar below messages, click to toggle

- [ ] **4.17** Meilisearch full-text search:
  - Index: public channel messages (id, channel_id, author_id, content, timestamp)
  - **Encrypted messages are NOT indexed** — by design, server cannot read them
  - Sync: new messages indexed on creation, deleted messages removed from index
  - `GET /api/v1/search?q=<query>&channel_id=<optional>&before=<optional>&after=<optional>`
  - Results: paginated, highlighted matches, permission-filtered (user can only search channels they have access to)

- [ ] **4.18** Message history pagination:
  - `GET /api/v1/channels/:id/messages?before=<cursor>&limit=50` — cursor-based, descending
  - `GET /api/v1/channels/:id/messages?after=<cursor>&limit=50` — ascending (for gap-fill)
  - Cursor: message ID (UUIDv7, time-ordered)
  - Include: message object, author object (denormalized), reactions, reply_to summary

- [ ] **4.19** Custom emoji:
  - Ecto schema: `custom_emojis` (id, server_id, name, file_id, creator_id)
  - `POST /api/v1/servers/:id/emojis` — upload custom emoji (max 256KB, square image)
  - `GET /api/v1/servers/:id/emojis` — list server's custom emojis
  - `DELETE /api/v1/servers/:id/emojis/:emoji_id` — delete
  - Usage in messages: `:emoji_name:` syntax, resolved client-side
  - Max 50 custom emojis per server (configurable)

- [ ] **4.20** Rich link previews:
  - Server-side URL unfurling via privacy-respecting proxy:
    - Server fetches URL metadata (Open Graph, Twitter Card)
    - Client never contacts the target URL directly (no IP leak)
    - Cache unfurled metadata (TTL: 24h)
  - Display: title, description, thumbnail (if available)
  - Configurable: disable per-server, disable per-channel, user preference

### Bot & Webhook System

- [ ] **4.21** Incoming webhooks:
  - Ecto schema: `webhooks` (id, channel_id, name, token, creator_id, avatar_url)
  - `POST /api/v1/servers/:id/webhooks` — create webhook for a channel
  - `GET /api/v1/servers/:id/webhooks` — list webhooks
  - `DELETE /api/v1/servers/:id/webhooks/:webhook_id` — delete
  - Webhook URL: `POST /api/v1/webhooks/:id/:token` — external services post messages
  - Webhook payload: `{ "content": "...", "username": "...", "avatar_url": "..." }`
  - Messages appear in channel with webhook name/avatar, marked as webhook message

- [ ] **4.22** Bot user accounts:
  - Special user type: `is_bot: true` in users table
  - Created via: `POST /api/v1/servers/:id/bots` — returns bot user + API token
  - Auth: API token in `Authorization: Bot <token>` header (no password, no E2E keys)
  - Bot tokens do not expire (but can be regenerated/revoked)

- [ ] **4.23** Bot permission scoping:
  - Bots assigned roles like regular users
  - Additional restriction: bots can be limited to specific channels
  - `bot_channels` join table: if populated, bot can only access listed channels
  - If empty, bot follows normal role-based permissions

- [ ] **4.24** Bot API:
  - Same REST + WebSocket API as regular clients
  - Messages sent by bots have `bot: true` flag
  - Bots can: send messages, read messages, react, manage messages (if permitted)
  - Bots cannot: manage roles, ban users, manage server (unless explicitly granted)

- [ ] **4.25** Webhook management UI:
  - Server settings → Webhooks panel
  - Create: name, channel, avatar (optional)
  - View: webhook URL (copyable), recent delivery logs
  - Delete with confirmation

### Additional Features

- [ ] **4.26** Notification preferences:
  - Per-channel: `all_messages` | `mentions_only` | `none`
  - `PUT /api/v1/users/me/notification-preferences` — update preferences
  - DND mode: suppress all notifications, configurable schedule
  - Quiet hours: time range when notifications are suppressed (e.g., 22:00-08:00)
  - Client: notification settings in channel context menu and user settings

- [ ] **4.27** Server discovery:
  - Opt-in: server operators can list their server in a public directory
  - `POST /api/v1/servers/:id/listing` — add to directory with description, tags, member count
  - `GET /api/v1/discovery/servers` — search/browse public servers
  - `GET /api/v1/discovery/servers?q=<query>&tags=<tag1,tag2>`
  - Directory is federated: nodes share their listed servers with federated peers

- [ ] **4.28** Data export (GDPR Article 20):
  - `POST /api/v1/users/me/export` — request data export
  - Oban job generates archive:
    - All messages authored by user (plaintext from public channels; ciphertext from encrypted channels with note that decryption requires client keys)
    - Profile data, settings, preferences
    - Upload history (file metadata, not file content — too large)
    - Server memberships, roles
  - Archive format: ZIP containing JSON files + README
  - Notify user when ready, download link valid for 24h
  - Rate limit: one export per 24 hours

- [ ] **4.29** Account portability:
  - `POST /api/v1/users/me/migration-export` — export for node migration:
    - User profile data
    - Identity keys (encrypted with user-provided passphrase)
    - Server membership list
    - **Not included:** message history (too large, stays on original node)
  - Import on new node: `POST /api/v1/auth/register-with-migration` — accepts migration export, creates user with existing identity keys
  - Federation redirect: old node can serve a redirect to new node for the user's ActivityPub actor

---

## Testing Checkpoint

- [ ] Create server with 3+ roles (admin, moderator, member), verify:
  - Permission inheritance works correctly
  - Channel overrides work (deny `send_messages` for `@everyone` in a specific channel)
  - Role priority prevents lower roles from modifying higher roles
- [ ] Test all moderation actions:
  - Mute user → verify they can't send messages → auto-unmute after duration
  - Kick user → verify removal → verify they can rejoin
  - Ban user → verify they can't rejoin → unban → verify they can rejoin
  - Report message → moderator sees report → takes action
- [ ] Test auto-moderation:
  - Configure word filter → send message containing blocked word → verify action taken
  - Configure mention spam limit → exceed it → verify message blocked
- [ ] Search via Meilisearch:
  - Send messages in public channel → search → verify results
  - Send messages in encrypted channel → search → verify they are NOT in results
- [ ] Webhook test:
  - Create webhook → POST message via curl → verify message appears in channel
  - View webhook delivery logs
- [ ] Bot test:
  - Create bot → use API token to send messages → verify `bot: true` flag
  - Restrict bot to specific channel → verify it can't access other channels
- [ ] Notification preferences:
  - Set channel to "mentions only" → send non-mention message → verify no notification
  - Set DND mode → verify all notifications suppressed
- [ ] Data export:
  - Request export → download archive → verify completeness and format
- [ ] Account portability:
  - Export from node-a → import on node-b → verify identity keys work

---

## Notes

- This is a feature-heavy phase with many independent components. Tasks can be parallelized.
- Auto-moderation for encrypted channels is inherently limited — the server can't inspect ciphertext. Document this as expected behavior.
- Bot accounts deliberately don't have E2E keys — bots operate at the server level and can only access unencrypted content. This is a design choice, not a gap.
- Rich link previews via server proxy add server load. Consider making this optional or using a dedicated microservice.
- Custom emoji storage counts against the server's storage quota.
