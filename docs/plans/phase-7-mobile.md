# Phase 7: Mobile (React Native / Expo)

**Duration:** 4-6 weeks
**Goal:** Native mobile clients for iOS and Android with full feature parity, leveraging shared `proto/` API client from Phase 6.
**Dependencies:** Phase 6 (shared code extraction, desktop client complete).
**Deliverable:** iOS and Android apps with push notifications, secure key storage, biometric auth, voice, and offline support.

---

## Tasks

### Expo Project Setup

- [ ] **7.1** Expo project setup (`client/mobile/`):
  - Expo SDK (latest stable) with development build (not Expo Go — need native modules)
  - Dependencies: expo-router (navigation), expo-secure-store, react-native-webrtc, sodium-react-native
  - Shared `@cairn/proto` linked as dependency
  - Build: EAS Build for iOS and Android

### Mobile UI

- [ ] **7.2** Mobile navigation and layout:
  - Tab navigation: Channels, DMs, Search, Settings
  - Channel list: swipe to mark read/mute
  - Message view: pull-to-refresh for history, auto-scroll for new messages
  - Swipe gestures: swipe right on message to reply, long-press for context menu (react, pin, delete)
  - Adaptive layout: iPhone SE to iPad Pro, Android phone to tablet
  - Dark mode: follow system preference or manual toggle

### Push Notifications

- [ ] **7.3** Push notifications:
  - Via Expo Push Notifications or self-hosted ntfy
  - **Privacy-first payload:** `{ "channel_id": "<uuid>", "count": 1 }` — NEVER include message content, sender name, or any identifiable information
  - On receive: update badge count, show generic notification ("New message in [channel name]")
  - Notification tap: open app to relevant channel
  - Token registration: `POST /api/v1/users/me/push-tokens`

### Voice

- [ ] **7.4** Voice via react-native-webrtc:
  - Test on physical iOS and Android devices (simulators have audio issues)
  - Audio session management: handle interruptions (phone call, other apps), audio routing (speaker, earpiece, Bluetooth)
  - Background audio: keep voice connected when app is backgrounded
  - Call UI: proximity sensor (turn off screen when held to ear), in-call notification

### Secure Key Storage

- [ ] **7.5** Secure key storage:
  - `expo-secure-store`: wraps iOS Keychain and Android Keystore
  - Store: E2E private keys, MLS state, auth tokens
  - Biometric protection: require Face ID/fingerprint to access keys (configurable)
  - Key size limit: expo-secure-store has 2KB limit per item → serialize and chunk larger data (MLS state)

### Background Sync

- [ ] **7.6** Background message sync:
  - iOS: Background App Refresh for unread count updates
  - Android: WorkManager for periodic sync
  - Sync: fetch unread counts per channel (NOT message content — preserve battery and bandwidth)
  - Badge count: update app icon badge with total unread count
  - Constraint: mobile OS limits background execution — keep sync minimal

### Biometric Auth

- [ ] **7.7** Biometric authentication:
  - Optional: enable in Settings → Security
  - On app open: prompt for Face ID / fingerprint / PIN
  - Protects: app access and key access
  - Timeout: configurable auto-lock (1min, 5min, 15min, never)
  - Implementation: `expo-local-authentication`

### Offline Cache

- [ ] **7.8** Offline message cache:
  - SQLite local database (expo-sqlite) for message cache
  - Cache recent messages per channel (last 100)
  - On network loss: display cached messages, queue outbound messages
  - On reconnect: sync — send queued messages, fetch missed messages
  - Clear cache: Settings → Storage → Clear Cache

---

## Testing Checkpoint

- [ ] iOS and Android builds via EAS Build
- [ ] Auth: login, register, 2FA, recovery codes on mobile
- [ ] Messaging: send, receive, edit, delete, react, reply
- [ ] E2E encryption: DMs and private channels work on mobile
- [ ] Voice: works on physical iOS and Android devices
- [ ] Push notifications: privacy-preserving payload, correct badge count
- [ ] Secure key storage: keys survive app reinstall (iOS Keychain backup)
- [ ] Biometric auth: Face ID/fingerprint prompt works
- [ ] Offline: cached messages display, queued messages send on reconnect

---

## Notes

- React Native + WebRTC on iOS requires careful audio session management. Budget extra testing time for iOS voice.
- expo-secure-store has a 2KB limit per item — MLS state may need to be chunked.
- Push notification payloads must never contain message content — the push notification service (APNs, FCM) can see the payload.
- F-Droid compatibility (no Google Play Services) is important — push notifications fall back to polling or self-hosted ntfy when FCM is unavailable.
- App Store review for encrypted messaging apps can take longer than usual. Submit early, expect reviewer questions about encryption and federation.
