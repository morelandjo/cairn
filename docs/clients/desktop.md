# Desktop App

The Cairn desktop app is built with Tauri and wraps the web client with native OS integrations.

## Download

Download the latest release for your platform from [GitHub Releases](https://github.com/morelandjo/cairn/releases):

| Platform | Format |
|----------|--------|
| macOS (Apple Silicon) | `.dmg` (aarch64) |
| macOS (Intel) | `.dmg` (x86_64) |
| Linux | `.AppImage`, `.deb` |
| Windows | `.msi` |

## First launch

1. Open the app
2. Enter your Cairn server URL (e.g., `https://cairn.example.com`)
3. Log in or create an account

The server URL is saved — you won't need to enter it again.

## Features

Everything in the [web client](web.md), plus:

- **System tray** — minimize to tray, badge for unread notifications
- **Native notifications** — OS-level push notifications
- **Secure key storage** — encryption keys are stored in the OS keychain (macOS Keychain, Windows Credential Manager, Linux Secret Service) instead of browser localStorage
- **Keyboard shortcuts** — global shortcuts for mute/deafen
- **Deep linking** — `cairn://` links open directly in the app (e.g., server invites)
- **Auto-update** — the app checks for updates and prompts you to install them
