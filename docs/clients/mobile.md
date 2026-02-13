# Mobile App

The Cairn mobile app is built with Expo and React Native.

## Install

Download from your app store, or sideload the APK/IPA from [GitHub Releases](https://github.com/morelandjo/cairn/releases).

## First launch

1. Open the app
2. Enter your Cairn server URL (e.g., `https://cairn.example.com`)
3. Log in or create an account

## Features

- Text messaging with threads, reactions, and pins
- Voice calls via WebRTC
- File uploads and link previews
- Server discovery and federation
- Push notifications (privacy-first — no message content or sender info in the push payload)
- Biometric authentication (Face ID, Touch ID, fingerprint)
- Offline mode with SQLite message cache and outbound queue

## Push notifications

Push notifications are delivered through the Expo Push API. For privacy, the notification payload contains only a signal that new activity is available — message content and sender information are never included. The app fetches the actual message data when you open the notification.

Manage your push notification preferences in **Settings > Notifications**.

## Known limitations

- **No MLS end-to-end encryption.** The MLS protocol relies on WebAssembly, which is not available in the React Native runtime. Private (E2EE) channels show a placeholder on mobile. Standard channels work normally.
- **No voice end-to-end encryption.** Voice encryption uses the Insertable Streams API, which is not available in React Native's WebRTC implementation. Voice calls work but are encrypted only at the transport level (DTLS-SRTP), not end-to-end.
