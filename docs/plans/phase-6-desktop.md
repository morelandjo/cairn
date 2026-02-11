# Phase 6: Shared Code Extraction + Desktop (Tauri)

**Duration:** 3-4 weeks
**Goal:** Extract platform-agnostic API client into `proto/`, then ship a native desktop app via Tauri v2 that wraps the existing web frontend.
**Dependencies:** All prior phases complete.
**Deliverable:** Desktop app (macOS, Windows, Linux) with system tray, native notifications, OS keychain, global shortcuts, auto-update, and deep linking.

---

## Tasks

### Shared Code Extraction

- [ ] **6a.1** Extract platform-agnostic API client into `proto/src/api/`:
  - `transport.ts` — `ApiTransport` interface with default `FetchTransport` implementation
  - `client.ts` — `ApiClient` class: base URL, token management, auto-refresh on 401, error handling
  - `auth.ts` — Auth API: register, login, refresh, me, TOTP, WebAuthn
  - `channels.ts` — Channel CRUD, messages, pins, threads, reactions
  - `servers.ts` — Server CRUD, membership, roles, categories
  - `moderation.ts` — Moderation actions, reports, auto-mod
  - `upload.ts` — File upload
  - `search.ts` — Search
  - `invites.ts` — Invite management
  - `notifications.ts` — Notification preferences
  - `discovery.ts` — Server discovery
  - `webhooks.ts` — Webhook management
  - `mls.ts` — MLS key packages, group info, commits
  - `voice.ts` — TURN/ICE credentials
  - `index.ts` — Re-exports all API modules
  - All code must be platform-agnostic (no DOM, no `window`, no `navigator`)

- [ ] **6a.2** Update `proto/` package exports:
  - Add `./api` subpath export in `package.json`
  - Re-export API modules from `proto/src/index.ts`

- [ ] **6a.3** Refactor `client/web/src/api/*.ts` to thin wrappers:
  - Each file imports and re-exports from `@murmuring/proto/api`
  - Socket/voice-socket files stay in web (Phoenix/browser-specific)

- [ ] **6a.4** Shared API client tests:
  - `proto/src/api/__tests__/client.test.ts` — mock transport, verify request building, token refresh, error handling
  - Run in Node.js to verify platform independence

### Desktop — Tauri v2 Scaffolding

- [ ] **6b.1** Tauri v2 project setup (`client/desktop/`):
  - `Cargo.toml` — tauri v2, tauri-plugin-* dependencies
  - `tauri.conf.json` — window config (1280×800, min 800×600), bundle targets (.dmg, .msi, .AppImage, .deb), identifier `dev.murmuring.desktop`
  - `src/main.rs` — entry point, plugin registration
  - `src/lib.rs` — Tauri command definitions
  - `capabilities/default.json` — Tauri v2 permissions
  - `build.rs` — Tauri build script
  - `build.devUrl`: `http://localhost:5173` (Vite dev server)
  - `build.frontendDist`: `../../client/web/dist`

- [ ] **6b.2** Build workflow verification:
  - `cd client/web && npm run build` → builds web frontend
  - `cd client/desktop && cargo tauri dev` → dev mode with Vite HMR
  - `cd client/desktop && cargo tauri build` → production build

### Desktop — System Tray, Notifications, Auto-Start

- [ ] **6c.1** System tray (Tauri v2 core):
  - `client/desktop/src/tray.rs` — tray icon, unread badge
  - Menu: Open, Mute Notifications, Quit
  - Click: show/hide window
  - Close button: minimize to tray (configurable)

- [ ] **6c.2** Native notifications (`tauri-plugin-notification`):
  - `client/desktop/src/notifications.rs` — notification bridge (JS → Rust commands)
  - Privacy-first: "New message in #channel" — never message content
  - Click → focus app, navigate to channel
  - Respect notification preferences (per-channel, DND)

- [ ] **6c.3** Auto-start (`tauri-plugin-autostart`):
  - Settings toggle, start-minimized option

- [ ] **6c.4** Desktop bridge:
  - `client/web/src/lib/desktopBridge.ts` — detect Tauri env, `invoke()` wrappers for native features

### Desktop — OS Keychain Integration

- [ ] **6d.1** Platform-specific keychain (`client/desktop/src/keychain.rs`):
  - macOS: `security-framework` crate
  - Windows: `windows` crate (Credential Manager)
  - Linux: `secret-service` (D-Bus), fallback to encrypted file
  - Tauri commands: `keychain_store`, `keychain_load`, `keychain_delete`

- [ ] **6d.2** Key storage abstraction:
  - `client/web/src/lib/keyStorage.ts` — abstract interface: Web=IndexedDB, Desktop=keychain via Tauri invoke
  - What's stored: identity key pair, signed prekey, MLS state, auth tokens

- [ ] **6d.3** Integrate key storage:
  - Update `client/web/src/stores/mlsStore.ts` — use `keyStorage` abstraction
  - Update `client/web/src/stores/authStore.ts` — use `keyStorage` for tokens

### Desktop — Global Keyboard Shortcuts

- [ ] **6e.1** Global shortcuts (`tauri-plugin-global-shortcut`):
  - `client/desktop/src/shortcuts.rs` — register global shortcuts, emit events
  - Push-to-talk: configurable (no default — must set)
  - Toggle mute: `CmdOrCtrl+Shift+M`
  - Toggle deafen: `CmdOrCtrl+Shift+D`

- [ ] **6e.2** Shortcut UI:
  - `client/web/src/components/ShortcutSettings.tsx` — key recorder settings
  - `client/web/src/lib/shortcutBridge.ts` — listen for shortcut events → voiceStore

### Desktop — Auto-Update, Deep Linking, Polish

- [ ] **6f.1** Auto-update (`tauri-plugin-updater`):
  - `client/desktop/src/updater.rs` — check GitHub Releases for new versions
  - `client/web/src/components/UpdateBanner.tsx` — "Update available" banner, "Restart to update" button

- [ ] **6f.2** Deep linking (`tauri-plugin-deep-link`):
  - `client/desktop/src/deep_link.rs` — `murmuring://` protocol handler
  - `murmuring://invite/<code>` → join server
  - `murmuring://channel/<id>` → navigate to channel

- [ ] **6f.3** WebRTC webview testing:
  - Test audio/video in WebView2 (Windows), WebKit (macOS), WebKitGTK (Linux)
  - Document Insertable Streams support per platform
  - `docs/decisions/webrtc-webview-matrix.md`

- [ ] **6f.4** CI addition:
  - Add `cargo check` for `client/desktop/` to `.github/workflows/ci.yml` (Linux only, needs `libwebkit2gtk-4.1-dev`)
  - Full cross-platform release pipeline deferred to Phase 8

---

## Testing Checkpoint

- [ ] `cargo tauri dev` launches app with web frontend
- [ ] System tray: icon, menu, close-to-tray
- [ ] Notification: new DM shows OS notification, click opens channel
- [ ] Keychain: keys persist across app restarts
- [ ] Global shortcut: mute hotkey works when unfocused
- [ ] Voice: audio works in Tauri webview (macOS test)
- [ ] `cargo tauri build` produces distributable
- [ ] Proto API client tests pass in Node.js

---

## Notes

- Tauri v2 runs web frontend in a native webview — React components, Zustand stores, and Phoenix WebSocket code all work unchanged.
- The shared extraction primarily benefits future mobile (React Native) and provides cleaner architecture.
- Socket/voice-socket modules stay in the web client — they use Phoenix JS and browser-specific APIs.
- WebRTC in WebKit (macOS) may have Insertable Streams limitations — document and plan workarounds.
