# Phase 5: Voice & Video with E2E Encryption

**Duration:** 6-10 weeks
**Goal:** Real-time voice and video using WebRTC + mediasoup SFU, with E2E encryption via insertable streams using MLS keys from Phase 2.
**Dependencies:** Phase 2 (MLS encryption — required for E2E voice keys), Phase 4 (moderation tools for voice channel moderation)
**Deliverable:** Voice and video channels with optional E2E encryption, screen sharing, and federation support.

---

## Tasks

### SFU Setup (mediasoup)

- [ ] **5.1** mediasoup Node.js sidecar (`sfu/`):
  - Express/Fastify HTTP API for Phoenix to communicate (or Unix domain socket for local deployment)
  - Endpoints:
    - `POST /rooms` — create a mediasoup Router (one per voice channel)
    - `DELETE /rooms/:id` — destroy Router when channel empties
    - `POST /rooms/:id/transports` — create WebRTC Transport for a participant
    - `POST /rooms/:id/producers` — create Producer (user sending audio/video)
    - `POST /rooms/:id/consumers` — create Consumer (user receiving audio/video)
    - `GET /health` — health check
  - Configuration via env vars: `MEDIASOUP_WORKERS` (number of worker processes, default: CPU cores), `MEDIASOUP_LOG_LEVEL`

- [ ] **5.2** Worker/Router/Transport architecture:
  - Workers: one per CPU core, handles media processing
  - Router: one per voice channel, manages Producers and Consumers
  - Transport: one per participant direction (send + receive = 2 transports per user)
  - Router RTP capabilities: advertise supported codecs to clients

- [ ] **5.3** Codec configuration:
  - Audio: Opus (mandatory) — 48kHz, stereo-capable, 32-128 kbps adaptive
  - Video: VP8 (mandatory), VP9 (optional, better quality/compression)
  - Prioritize low latency: DTX (discontinuous transmission) for Opus, temporal scalability for VP8/VP9
  - Simulcast: clients send multiple quality layers, SFU selects appropriate layer per consumer

- [ ] **5.4** TURN server integration:
  - Essential for NAT traversal (many users behind symmetric NATs)
  - Option A: Bundle coturn configuration in `deploy/` (Docker Compose service)
  - Option B: Document external TURN setup (Twilio, Cloudflare, self-hosted)
  - TURN credentials: short-lived via HMAC-based token generation (`GET /api/v1/voice/turn-credentials`)
  - STUN: use public Google/Cloudflare STUN servers as fallback

- [ ] **5.5** SFU monitoring:
  - `GET /health` — returns worker count, active rooms, total producers/consumers
  - Metrics: active rooms, participants per room, bandwidth in/out, CPU usage per worker
  - Alert thresholds: CPU > 80%, bandwidth saturation, worker crash/restart

### Signaling (Phoenix Channels)

- [ ] **5.6** `VoiceChannel` Phoenix Channel:
  - Topic: `voice:channel_uuid`
  - `join/3`: verify user has `use_voice` permission, create mediasoup Transport via SFU API
  - `handle_in("connect_transport", ...)`: complete DTLS handshake params
  - `handle_in("produce", ...)`: user starts sending audio/video → create Producer on SFU
  - `handle_in("consume", ...)`: user wants to receive from another participant → create Consumer on SFU
  - `handle_in("resume_consumer", ...)`: resume paused consumer
  - `handle_in("leave", ...)`: disconnect transports, clean up producers/consumers
  - `terminate/2`: clean up on disconnect

- [ ] **5.7** Signaling flow:
  1. User clicks "Join Voice" → client joins `voice:channel_uuid`
  2. Server creates send + receive WebRTC Transports via SFU API
  3. Server sends transport parameters (ICE candidates, DTLS fingerprint) to client
  4. Client creates `RTCPeerConnection`, connects transport
  5. Client produces audio → server creates Producer → notifies other participants
  6. Other clients create Consumers for the new Producer
  7. Audio flows: Client → SFU → Other Clients
  8. On leave: close transports, remove producers/consumers, notify peers

- [ ] **5.8** Voice presence:
  - Track who is in each voice channel via Phoenix Presence
  - Broadcast events: `user_joined_voice`, `user_left_voice`
  - Per-user state: `muted`, `deafened`, `speaking`, `video_on`, `screen_sharing`
  - Client sidebar: voice channel shows connected users with status icons

- [ ] **5.9** Server-side voice moderation:
  - Moderator mute: `handle_in("mod_mute", %{"user_id" => id})` — pause user's Producer on SFU, notify client
  - Moderator disconnect: `handle_in("mod_disconnect", %{"user_id" => id})` — force-leave user from voice
  - Requires `manage_channels` or `kick_members` permission
  - Logged in moderation log

### E2E Encrypted Voice

- [ ] **5.10** WebRTC Insertable Streams (Encoded Transforms):
  - API: `RTCRtpSender.createEncodedStreams()` / `RTCRtpReceiver.createEncodedStreams()`
  - Transform pipeline: encode → **encrypt** → send → receive → **decrypt** → decode
  - Encryption: AES-128-GCM per frame, key derived from MLS epoch secret (for encrypted channels) or ephemeral shared key (for ad-hoc voice)
  - Frame format: `[IV (12 bytes)] [encrypted payload] [GCM tag (16 bytes)]`

- [ ] **5.11** Voice encryption key derivation:
  - For MLS-encrypted channels: derive voice key from current MLS epoch secret using HKDF
    - `voice_key = HKDF-Expand(epoch_secret, "cairn-voice-key", 16)`
  - For non-encrypted channels with opt-in voice E2E: ephemeral key exchange via Double Ratchet-style DH
  - Key rotation: on MLS epoch change, derive new voice key, brief transition period where both keys are valid

- [ ] **5.12** Client-side audio level detection:
  - SFU cannot inspect encrypted audio frames for speaking detection
  - Client-side: use Web Audio API `AnalyserNode` to detect audio levels locally
  - Broadcast speaking state via signaling channel: `speaking_start` / `speaking_stop` events
  - Threshold: configurable, default -40dB

- [ ] **5.13** Latency benchmarking:
  - Target: sub-200ms round-trip with E2E encryption enabled
  - Measure: end-to-end audio latency (sender → SFU → receiver → decrypt → playback)
  - Overhead budget: encryption/decryption should add <5ms per frame
  - Test with varying participant counts: 2, 5, 10, 25

- [ ] **5.14** Graceful fallback for unsupported browsers:
  - Check for Insertable Streams API support at runtime
  - If not supported (e.g., older Firefox):
    - Offer non-E2E voice with clear UI indicator: "Voice is not end-to-end encrypted in this browser"
    - User consent required before joining without E2E
  - Feature detection: `typeof RTCRtpSender.prototype.createEncodedStreams === 'function'`

### Federated Voice

- [ ] **5.15** Federated voice signaling:
  - Remote users connect directly to the hosting node's SFU
  - Signaling proxied through federation: remote node relays WebSocket signaling to hosting node
  - Authentication: remote user's identity verified via federation credentials
  - SFU sees remote user as a regular participant (transparent)

- [ ] **5.16** Voice channel capacity:
  - Configurable per-channel limit: default 25 participants
  - Hard maximum: 100 (mediasoup practical limit per Router)
  - Reject join attempts when at capacity with clear error message
  - Priority: channel moderators can always join (kick lowest-priority user if full)

- [ ] **5.17** Bandwidth adaptation:
  - mediasoup bandwidth estimation: track available bandwidth per consumer
  - Simulcast layer selection: SFU selects appropriate video quality layer based on consumer bandwidth
  - Audio: Opus DTX and bitrate adaptation (lower quality for poor connections)
  - Client-side: display connection quality indicator based on reported stats

### Web Client Voice UI

- [ ] **5.18** Voice connection panel:
  - "Join Voice" button on voice channels
  - Connected state: self-mute toggle, self-deafen toggle, disconnect button
  - Floating voice bar at bottom of screen when connected (persists across channel navigation)
  - Voice channel in sidebar shows connected users

- [ ] **5.19** Active speakers display:
  - User avatars with speaking indicator (green ring/glow when speaking)
  - Audio level visualization (volume bars or ring intensity)
  - Sort by most recently speaking (or fixed order)

- [ ] **5.20** Audio processing:
  - WebRTC constraints: `echoCancellation: true`, `noiseSuppression: true`, `autoGainControl: true`
  - Audio input/output device selection (enumerate via `navigator.mediaDevices.enumerateDevices()`)
  - Microphone test: loopback playback in settings

- [ ] **5.21** Connection quality indicator:
  - Display: latency (ms), packet loss (%), codec info
  - Source: `RTCPeerConnection.getStats()` polled every 2 seconds
  - Visual: green/yellow/red indicator based on quality thresholds
  - Poor quality warning: "Your connection quality is poor. Consider turning off video."

- [ ] **5.22** Push-to-talk:
  - Settings → Voice → Input Mode: "Voice Activity" (default) or "Push to Talk"
  - Push-to-talk key: configurable (default: unset, user must choose)
  - Implementation: mute audio Producer by default, unmute on key hold
  - Global hotkey support: works even when app is not focused (desktop/Tauri only — Phase 6)

- [ ] **5.23** Screen sharing:
  - `navigator.mediaDevices.getDisplayMedia()` → create video Producer for screen capture
  - Share button in voice panel
  - Shared screen appears as a large video feed for all participants
  - Options: share entire screen, application window, or browser tab
  - Stop sharing button (prominent, hard to miss)
  - Limit: one screen share per channel at a time (configurable)

### Video Calls

- [ ] **5.24** Video support:
  - Camera toggle button in voice panel
  - Video Producer created when camera enabled
  - Video layout: grid view (all participants equal size) or spotlight view (active speaker large, others small)
  - Layout auto-switch: spotlight when someone is screen sharing, grid otherwise

- [ ] **5.25** Video quality settings:
  - Resolution options: 360p, 720p (default), 1080p
  - Frame rate: 15fps (low bandwidth), 30fps (default)
  - Simulcast: send 3 quality layers, SFU selects per consumer
  - User setting: "Prefer performance" vs "Prefer quality"

---

## Testing Checkpoint

- [ ] 3+ users in voice channel:
  - Audio quality is clear, no echoing, no feedback loops
  - Speaking indicators work correctly
  - Mute/deafen work as expected
- [ ] Moderator actions:
  - Moderator mutes a user → user's audio stops for all participants
  - Moderator disconnects a user → user is removed from voice
- [ ] E2E encrypted voice:
  - Enable E2E for a channel → verify SFU cannot decode audio frames
  - Inspect SFU logs/metrics → confirm encrypted payload is opaque
  - Decrypt locally → audio is clear
- [ ] Federated voice:
  - User on node-b joins voice channel hosted on node-a → audio works
  - Latency acceptable for cross-node voice
- [ ] TURN fallback:
  - Simulate restrictive NAT (block direct UDP) → verify TURN relay is used → audio still works
- [ ] Latency benchmark:
  - Measure with and without E2E encryption
  - Target: <200ms round-trip, <5ms encryption overhead per frame
- [ ] Screen sharing:
  - Share screen → all participants see shared screen
  - Stop sharing → screen feed stops
- [ ] Video:
  - Enable camera → video visible to all participants
  - Test grid and spotlight layouts
  - Test simulcast: participants with poor connections get lower quality
- [ ] Capacity:
  - 25 users in voice channel → verify system remains stable
  - Attempt to join at capacity → verify graceful rejection

---

## Notes

- mediasoup is CPU-intensive. A $5 VPS may struggle with more than 10-15 concurrent voice users. Document minimum hardware requirements for voice.
- Insertable Streams (Encoded Transforms) are well-supported in Chromium browsers but lagging in Firefox. The graceful fallback (task 5.14) is essential.
- E2E encrypted voice means the SFU is a dumb relay — it cannot mix audio, detect silence, or do server-side noise reduction. All that must happen client-side.
- Screen sharing + E2E encryption is supported — screen frames are encrypted just like camera frames.
