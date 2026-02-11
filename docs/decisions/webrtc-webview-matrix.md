# WebRTC Webview Compatibility Matrix

Tauri v2 uses the OS webview engine. WebRTC support varies by platform.

## Platform Matrix

| Platform | Webview Engine | WebRTC Audio/Video | Insertable Streams | Notes |
|----------|---------------|-------------------|-------------------|-------|
| macOS | WebKit (WKWebView) | Yes | Partial (Safari 15.4+) | Uses `RTCRtpScriptTransform` instead of `createEncodedStreams()`. Need to check if WebKit in Tauri exposes this. |
| Windows | WebView2 (Chromium) | Yes | Yes | Full support via Chromium Insertable Streams API. Best platform for E2E voice. |
| Linux | WebKitGTK | Yes (with caveats) | No | WebKitGTK lags behind Safari. Insertable Streams not available. Fallback: disable E2E voice encryption on Linux desktop. |

## Key Considerations

### Insertable Streams (E2E Voice Encryption)

Our voice E2E encryption uses Insertable Streams to encrypt/decrypt audio frames before they leave/enter the WebRTC pipeline:
- **Chromium** (Windows): `RTCRtpSender.createEncodedStreams()` — fully supported
- **Safari/WebKit** (macOS): `RTCRtpScriptTransform` — supported since Safari 15.4, but the API surface differs from Chromium
- **WebKitGTK** (Linux): No Insertable Streams support

### Fallback Strategy

1. **Feature detection**: Check for `createEncodedStreams` or `RTCRtpScriptTransform` at runtime
2. **Graceful degradation**: If neither is available, voice works without E2E encryption
3. **UI indicator**: Show a lock icon when E2E voice encryption is active, warning icon when not
4. Our existing `supportsInsertableStreams()` function in `proto/src/crypto/voice.ts` handles detection

### Audio Device Enumeration

`navigator.mediaDevices.enumerateDevices()` works on all three webview engines.
No workarounds needed for device selection.

### Tested Configurations

| OS | Version | Webview | Audio | Video | Screen Share | E2E Voice |
|----|---------|---------|-------|-------|-------------|-----------|
| macOS 14+ | Sonoma | WebKit | TBD | TBD | TBD | TBD |
| Windows 11 | 23H2 | WebView2 | TBD | TBD | TBD | TBD |
| Ubuntu 24.04 | Noble | WebKitGTK 2.44 | TBD | TBD | TBD | TBD |

*To be filled in during Phase 6 testing.*

## Decision

- Ship desktop app on all platforms
- Voice works everywhere (audio/video)
- E2E voice encryption: best-effort with feature detection
- Document that Linux desktop users get voice without E2E encryption until WebKitGTK adds Insertable Streams
- macOS requires testing `RTCRtpScriptTransform` compatibility in WKWebView context
