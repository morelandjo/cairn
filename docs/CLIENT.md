# Client User Guide

## Overview

Cairn is available on three platforms:

| Platform | Technology | Distribution |
|----------|-----------|-------------|
| **Web** | React + Vite | Served by the Cairn server (no install needed) |
| **Desktop** | Tauri v2 (wraps web client) | GitHub Releases (macOS, Windows, Linux) |
| **Mobile** | React Native + Expo | App Store (iOS) / Google Play (Android) |

All clients share the same core protocol library (`@cairn/proto`) for API calls, encryption, and type definitions.

---

## System Requirements

### Web

| Browser | Minimum Version |
|---------|----------------|
| Chrome / Chromium | 90+ |
| Firefox | 90+ |
| Safari | 15+ |
| Edge | 90+ |

Voice E2E encryption requires Insertable Streams support (Chrome/Edge 94+).

### Desktop

| OS | Minimum Version |
|----|----------------|
| macOS | 11 (Big Sur)+ |
| Windows | 10+ |
| Linux | Ubuntu 20.04+ / equivalent |

Approximately 150 MB disk space. Window: 1280x800 default, 800x600 minimum.

### Mobile

| OS | Minimum Version |
|----|----------------|
| iOS | 16+ |
| Android | 10+ |

Permissions: Microphone (voice calls), Camera (video calls), Notifications, Face ID/Touch ID (optional biometric lock).

---

## Installation

### Web

No installation required. Navigate to your server's URL in a supported browser (e.g., `https://cairn.example.com`).

### Desktop

Download the latest release for your platform from the project's GitHub Releases page. The app auto-updates when new versions are available.

On first launch, you'll see the **Server Connect** screen where you enter your server URL. The app validates the connection by checking the server's `/health` endpoint. Your five most recent servers are saved for quick reconnection.

### Mobile

Install from the App Store (iOS) or Google Play (Android). On first launch, enter your server URL in the **Server Connect** screen.

---

## Connecting to a Server

### Web

Open the server URL directly in your browser. If the server serves the SPA (single-page application), you'll see the login screen immediately.

### Desktop & Mobile

1. Launch the app
2. Enter the server URL (e.g., `https://cairn.example.com`)
3. The app verifies the connection
4. Proceed to login or registration

---

## Account Management

### Registration

1. Click **Register** on the login screen
2. Enter a username (unique), display name (optional), and password (8+ characters)
3. After registration, **recovery codes** are displayed — save these in a secure location. They are needed to recover your account if you lose access to your 2FA device, and to rotate your rotation key in case of key compromise.
4. You are automatically logged in
5. Your cryptographic identity (`did:cairn:...`) is generated automatically from your signing and rotation keys. This DID is permanent and survives key rotations.

### Login

1. Enter your username and password
2. If 2FA is enabled, you'll be prompted for a TOTP code
3. On success, the app connects to the server via WebSocket for real-time updates

### Session Persistence

Your session tokens are stored securely:
- **Web:** Browser localStorage
- **Desktop:** OS keychain (macOS Keychain, Windows Credential Manager, Linux Secret Service)
- **Mobile:** Expo Secure Store (encrypted, with chunking for items > 2 KB)

Sessions are automatically restored on app launch. If your access token expires, the app silently refreshes it.

### Two-Factor Authentication

Cairn supports two 2FA methods:

- **TOTP** (Time-based One-Time Password) — works with any authenticator app (Google Authenticator, Authy, etc.)
- **WebAuthn** — hardware security keys (YubiKey, etc.) or platform authenticators (Touch ID, Windows Hello)

Enable 2FA from your security settings.

### Recovery Codes

Recovery codes are shown once during registration. Each code can be used once to bypass 2FA. Store them securely offline.

### Password Change

Change your password from the security settings page. This invalidates existing sessions.

---

## Servers

Servers are the top-level organizational unit (similar to Discord servers or guilds). Each server has its own channels, roles, and members.

### Server List

The left sidebar shows all servers you've joined, grouped by instance. Your **home instance** servers appear at the top, followed by remote instances with domain labels and connection status indicators. Click a server icon to switch to it. The **Home** icon shows your direct messages.

### Creating a Server

1. Click the **+** button in the server sidebar
2. Enter a server name and optional description
3. You become the server owner with full permissions
4. Default roles (@everyone, Moderator, Admin, Owner) are created automatically

### Joining a Server

Join via:
- **Invite link** — someone shares a link like `https://server.com/invite/abc123`
- **Invite code** — enter the code directly
- **Server Discovery** — browse the public server directory
- **Federated invite** — join a server on a remote instance via a federated invite link. Your home instance issues a signed authentication token so you don't need to create a new account.

### Joining Remote Servers

When you join a server on a different Cairn instance:

1. Click the globe icon in the server sidebar or follow a federated invite link
2. Your home instance issues a federated authentication token
3. The remote instance verifies your identity via your DID operation chain
4. Your client establishes a direct WebSocket connection to the remote instance
5. The remote server appears in your sidebar under its instance domain

Remote servers show a connection status indicator (connected/connecting/disconnected). Your messages on remote servers display as `username@home-instance` to other users.

### Server Discovery

The discovery page lists servers that have opted in to the public directory. You can filter by tags and see member counts.

---

## Channels

### Channel Types

| Type | Icon | Description |
|------|------|-------------|
| **Public** | # | Visible to all server members |
| **Private** | Lock | End-to-end encrypted (MLS), invite-only |
| **Voice** | Speaker | Real-time voice and video communication |

### Categories

Channels can be organized into categories (collapsible groups in the sidebar). Server admins can create, rename, reorder, and delete categories.

### Creating Channels

1. Click the **+** button next to a channel category or in the channel sidebar
2. Enter a name, select the type (public/private/voice), and add an optional description
3. For private channels, select initial members — an MLS group is created automatically

### Channel Sidebar

The channel sidebar shows:
- Categories with their channels
- Channel type indicators (public #, private lock, voice speaker)
- Unread indicators

---

## Messaging

### Sending Messages

Type in the message input at the bottom of the channel view and press **Enter** to send. Use **Shift+Enter** for multi-line messages.

### Replies

Click the reply button on any message to start a threaded reply. A preview of the original message appears above the input. Press **Escape** to cancel the reply.

### Reactions

Click the reaction button on a message to open the emoji picker. Select an emoji to add your reaction. Click an existing reaction to toggle yours.

### Pins

Pin important messages to make them easy to find. Click the pin icon in the channel header to view all pinned messages. Pinning requires the `manage_messages` permission.

### Editing & Deleting

- **Edit:** Click the edit option on your own messages
- **Delete:** Click the delete option on your own messages, or on any message if you have `manage_messages` permission

### Typing Indicators

When you're typing, other channel members see a typing indicator. This updates every 2 seconds and times out after 3 seconds of inactivity.

### File Uploads

Drag and drop files into the message input or click the file upload button. Uploaded files are inserted as markdown links in your message. Upload size limits are configured by the server administrator.

### Link Previews

URLs in messages are automatically previewed with title, description, and image metadata. Link previews are fetched server-side to prevent SSRF attacks.

### Custom Emoji

Servers can have custom emoji uploaded by admins. Use them in messages and reactions. Emoji requirements are set by the server.

### Search

Click the search icon in the channel header to search messages. Search is powered by Meilisearch and supports full-text queries across channels you have access to.

---

## Voice & Video

### Joining a Voice Channel

Click a voice channel in the sidebar to join. Your browser/app will request microphone permission.

### Controls

| Action | Button | Desktop Shortcut |
|--------|--------|-----------------|
| Toggle Mute | Microphone icon | `Cmd/Ctrl+Shift+M` |
| Toggle Deafen | Headphone icon | `Cmd/Ctrl+Shift+D` |
| Toggle Video | Camera icon | — |
| Screen Share | Monitor icon | — |
| Disconnect | Phone icon | — |
| Push-to-Talk | — | Configurable |

### Voice Connection Bar

When connected to a voice channel, a bar appears showing the channel name, participant count, and quick controls (mute, deafen, disconnect).

### Participants

The voice panel shows all connected participants with indicators for:
- Speaking (highlighted border)
- Muted (M indicator)
- Deafened (D indicator)
- Video active

### Video Grid

When participants enable video or screen share, a responsive grid layout displays video tiles with name overlays.

### Voice Settings

Access voice settings to configure:
- Input/output device selection
- Echo cancellation
- Noise suppression
- Automatic gain control
- Volume levels

### E2E Encryption

Voice and video are encrypted end-to-end on supported platforms using Insertable Streams:
- A 128-bit AES-GCM key is derived from the MLS epoch secret via HKDF
- Each audio/video frame is encrypted with a unique IV
- Key rotation occurs automatically when group membership changes

### Platform Limitations

| Feature | Web (Chrome/Edge) | Web (Firefox/Safari) | Desktop | Mobile |
|---------|-------------------|---------------------|---------|--------|
| Voice | Yes | Yes | Yes | Yes |
| Video | Yes | Yes | Yes | No |
| Screen Share | Yes | Yes | Yes | No |
| Voice E2E Encryption | Yes | No | Yes | No |

Mobile voice uses `react-native-webrtc` with the `ReactNativeUnifiedPlan` handler. Insertable Streams (required for voice E2E encryption) are not available in React Native.

---

## End-to-End Encryption

Cairn provides end-to-end encryption for private channels and 1:1 messages, ensuring the server cannot read message content.

### MLS (Messaging Layer Security)

Private channels use the MLS protocol for group encryption:
- Each user maintains a set of **key packages** (uploaded in batches of 50, minimum 10 maintained)
- When a private channel is created, an MLS group is initialized
- Members receive **welcome messages** with the group state
- Messages are encrypted with AES-128-GCM using keys derived from the group's epoch secret
- Membership changes (joins/leaves) trigger **commits** that update group keys

### Double Ratchet (X3DH)

1:1 private messaging uses the X3DH key agreement protocol and Double Ratchet for forward secrecy.

### Key Backup

Back up your encryption keys to the server for recovery on new devices:

1. Go to **Security Settings**
2. Click **Backup Keys**
3. Enter a strong passphrase — your keys are encrypted client-side before upload
4. To restore, click **Restore Backup** and enter the same passphrase

### Safety Numbers

Verify a contact's identity by comparing safety numbers. Open the **Safety Number** dialog for a user to see a visual representation of their public key and their DID (`did:cairn:...`). DIDs work for cross-instance verification — the same DID identifies a user regardless of which instance you're viewing them from.

### Mobile Limitations

MLS end-to-end encryption is **not available on mobile** because the MLS WASM library requires WebAssembly support not available in the Hermes JavaScript engine. Private channels on mobile show a placeholder indicating encryption is unavailable.

---

## Notifications

### Desktop

Native OS notifications via the Tauri notification plugin. Privacy-preserving: notifications show a generic alert without message content.

### Mobile

Push notifications via the Expo Push API:
- Privacy-first: the push payload contains only a notification count, never message content or sender information
- Register/unregister push tokens automatically on login/logout
- Tap a notification to open the relevant conversation

### Web

Browser notification API. Must be granted permission when prompted.

### Notification Preferences

Configure per-server and per-channel notification settings:
- All messages
- Mentions only
- None

---

## Settings

### General

- **Theme:** Light/dark mode
- **Notifications:** Per-channel preferences

### Security

- **Two-Factor Authentication:** Enable/disable TOTP and WebAuthn
- **Cryptographic Identity (DID):** View your `did:cairn:...` identifier (click to copy)
- **Key Rotation:** Rotate your signing key (DID stays the same). Use if you suspect key compromise.
- **Key Backup:** Backup and restore encryption keys (including rotation key)
- **Key Package Status:** View MLS key package count
- **Recovery Codes:** View remaining recovery codes (also needed for rotation key recovery)

### Desktop-Specific

- **System Tray:** Minimize to tray on close
- **Auto-Start:** Launch on system startup
- **Global Shortcuts:** Configure mute/deafen/push-to-talk keys
- **Auto-Update:** Automatically install updates

### Mobile-Specific

- **Server URL:** Change the connected server
- **Biometric Lock:** Require Face ID / Touch ID / fingerprint to open the app
- **Offline Mode:** Cache messages locally with SQLite for offline access
- **Push Notifications:** Enable/disable push notifications

### Data Export (GDPR)

Request a full export of your data:
1. Go to Settings
2. Click **Export My Data**
3. A download link will be provided when the export is ready

The export includes your messages, uploaded files, account information, and encryption keys (if backed up). A portable format option is also available.

---

## Keyboard Shortcuts

Available on Web and Desktop:

### Navigation

| Action | Shortcut |
|--------|----------|
| Send message | `Enter` |
| New line | `Shift+Enter` |
| Cancel reply | `Escape` |

### Voice (Desktop global shortcuts)

| Action | Default Shortcut |
|--------|-----------------|
| Toggle Mute | `Cmd/Ctrl+Shift+M` |
| Toggle Deafen | `Cmd/Ctrl+Shift+D` |
| Push-to-Talk | Configurable in settings |

Shortcuts are configurable in the desktop app's settings under **Shortcut Settings**.

---

## Offline Mode (Mobile)

The mobile app includes an SQLite-based offline cache:

- **Cached messages:** Up to 100 messages per channel, stored locally
- **Outbound queue:** Messages composed while offline are queued and sent automatically when connectivity is restored
- **Sync:** When the app comes back online, the sync manager retries queued messages and refreshes cached data

Enable offline mode in mobile settings.

---

## Federation & Portable Identity

Cairn uses portable cryptographic identity (`did:cairn`) so you can participate across multiple instances with a single account.

### How It Works

- **One account, many servers:** Your identity is a self-certifying DID derived from your cryptographic keys. Register once on your home instance, then join servers on any federated instance without re-registering.
- **Federated auth tokens:** When you join a remote server, your home instance issues a time-limited, node-signed token. The remote instance verifies it and creates a federated membership for you.
- **Cross-instance DMs:** You can DM users on other instances. The DM channel lives on the initiator's instance; the recipient connects via federated auth. See [Cross-Instance DMs](#cross-instance-dms) below.
- **Transparent messaging:** Federated messages appear alongside local messages. Remote users are shown with an `@instance` suffix and a globe icon.
- **Identity verification:** Your DID is stable across key rotations and verifiable by any instance independently via the hash-chained operation log.

### Multi-Instance Client

Your client maintains WebSocket connections to each instance you have servers on. The sidebar groups servers by instance with connection status indicators. Switching between servers on different instances is seamless.

### Key Rotation

If you suspect your signing key is compromised:

1. Go to **Security Settings**
2. Click **Rotate Signing Key**
3. Your rotation key signs a new operation in your DID chain
4. Your DID stays the same, but the old signing key is rejected
5. All instances you're connected to will see the updated key

For rotation key compromise, use your recovery codes to rotate the rotation key itself.

### Cross-Instance DMs

You can send direct messages to users on other Cairn instances:

#### Sending a DM (Initiator)

1. Open a shared server's member list
2. Click the **DM** button on a federated user's profile (users with a globe icon and `@instance` suffix)
3. Confirm the DM request in the dialog — your client fetches the recipient's encryption keys via federation
4. The DM channel is created on **your instance** with E2E encryption (X3DH + Double Ratchet)
5. A DM hint is sent to the recipient's home instance as a notification
6. You can see the request status in **DM Requests** (sent tab)

#### Receiving a DM (Recipient)

1. You receive a real-time DM request notification
2. Click **DM Requests** in the channel header to see pending requests
3. Each request shows the sender's username, DID, and home instance
4. Choose to **Accept**, **Reject**, or **Block**:
   - **Accept:** Your client connects to the sender's instance via federated auth and joins the DM channel
   - **Reject:** The request is dismissed
   - **Block:** The request is rejected and the sender's DID is added to your block list (they cannot send future requests)

#### Privacy Notes

- DM messages are **end-to-end encrypted** — the hosting instance only sees ciphertext
- DM messages are **never** sent over federation (no ActivityPub activity for DM content)
- Only the DM hint (sender DID, channel ID) crosses instances — a lightweight notification
- Rate limits prevent spam: max 10 requests/hour, max 5 pending per recipient

Your portable identity means you can join any federated instance you choose — your home server admin cannot restrict where you go. Server administrators can only control which *inbound* remote instances their server accepts activities from (e.g. blocking a malicious instance from delivering spam). This does not prevent their users from visiting or joining servers on that instance. See the [Administration Guide](ADMINISTRATION.md#federation-admin) for details on instance-level federation management.

---

## Troubleshooting

### Can't connect to server

- Verify the server URL is correct and includes `https://`
- Check that the server is running: visit `/health` in a browser
- On mobile, ensure you're using the full URL (absolute, not relative)

### Messages not sending

- Check your internet connection
- On mobile, check if offline mode queued the message (it will retry automatically)
- Verify you have `send_messages` permission in the channel

### Voice not working

- Grant microphone permission when prompted
- Check that your browser/app has access to the correct audio device
- Ensure TURN/STUN ports are not blocked by your network
- On corporate networks, WebRTC may be blocked — contact your network administrator

### Encryption issues

- If private channel messages show as unreadable, your MLS state may be out of sync. Leave and rejoin the channel.
- Check Security Settings to ensure you have sufficient key packages
- On mobile, private channels are not encrypted (MLS WASM not supported)

### Desktop app not updating

- Check for updates manually in the app settings
- Ensure the app has write access to its installation directory
- On macOS, the app must be in `/Applications` for auto-update to work
