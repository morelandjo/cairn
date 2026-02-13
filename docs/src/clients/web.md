# Web Client

The web client is served directly by the Cairn server as a single-page application — there is no separate setup required.

## Access

Open your Cairn instance in a browser:

```
https://your-domain.com
```

The server injects your instance's configuration (domain, feature flags) into the page at load time, so everything works out of the box.

## Supported browsers

Any modern browser with WebSocket and WebCrypto support:

- Chrome / Edge 90+
- Firefox 90+
- Safari 15+

## Features

The web client supports all Cairn features:

- Text messaging with threads, reactions, and pins
- Voice and video calls with end-to-end encryption (via Insertable Streams)
- Screen sharing and simulcast video
- MLS group encryption for private channels
- File uploads and link previews
- Full-text search
- Server discovery and federation
