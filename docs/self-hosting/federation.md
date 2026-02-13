# Federation

Federation allows users on different Cairn instances to communicate with each other — join servers, send messages, and participate in voice channels across instances.

## What federation enables

- Users can join servers hosted on other Cairn instances
- Messages are delivered between instances in real time
- Voice calls work across instances via relay
- Each user has a portable cryptographic identity (`did:cairn`) that works everywhere

## What federation does not do

- **DMs are never federated.** Direct messages stay on your home instance and are never sent to remote servers.
- **Metadata is stripped.** When forwarding messages to other instances, unnecessary metadata is removed to protect user privacy.

## Enable federation

Set two environment variables in your `.env`:

```sh
cairn-ctl config FEDERATION_ENABLED true
cairn-ctl config CAIRN_DOMAIN cairn.example.com
cairn-ctl restart
```

Or edit `/opt/cairn/.env` directly:

```env
FEDERATION_ENABLED=true
CAIRN_DOMAIN=cairn.example.com
```

### Requirements

- **SSL is mandatory.** Federation forces `FORCE_SSL=true` — you cannot disable SSL while federation is enabled.
- **A publicly reachable domain.** Other instances need to reach your server over HTTPS.
- **A reverse proxy with TLS** — see [Reverse Proxy](reverse-proxy.md).

## How it works

### Discovery

Each federated instance publishes a well-known endpoint at:

```
https://cairn.example.com/.well-known/cairn
```

This returns the instance's public Ed25519 signing key, which other instances use to verify message authenticity.

### Authentication

Federation uses HTTP Signatures (RFC 9421) to authenticate requests between instances. Each instance has an Ed25519 key pair stored in `/opt/cairn/keys/`. The key is generated automatically on first startup when federation is enabled.

### Identity

Users are identified across instances by their DID (Decentralized Identifier):

```
did:cairn:<base58-encoded-hash>
```

A DID is stable and never changes, even if a user rotates their signing keys. Users carry their identity with them when joining servers on other instances.

## Key rotation

Rotate your instance's federation signing key:

```sh
# Via the admin API
curl -X POST https://cairn.example.com/api/v1/admin/federation/rotate-key \
  -H "Authorization: Bearer <admin-token>"
```

Key rotation is transparent to other instances — the new key is published at the well-known endpoint and other instances will pick it up automatically.

## Managing federation

List known federation nodes:

```sh
cairn-ctl federation list
```

This shows all remote instances your server has communicated with and their current status.

## Rate limiting

Inbound federation requests are rate-limited to prevent abuse. The server applies per-instance limits on incoming ActivityPub deliveries.

## Disabling federation

```sh
cairn-ctl config FEDERATION_ENABLED false
cairn-ctl restart
```

Existing federated data (remote users, memberships) will remain in the database but no new federation activity will occur.
