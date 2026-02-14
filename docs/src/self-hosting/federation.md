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

- **A reachable address.** Other instances need to reach your server — either a domain name or an IP address.
- **HTTPS is strongly recommended.** Use a reverse proxy with TLS — see [Reverse Proxy](reverse-proxy.md). Federation works without HTTPS, but traffic will be unencrypted (see [Insecure Federation](#insecure-federation) below).

## Transport security model

Cairn distinguishes between two layers of encryption:

- **Transport encryption (HTTPS):** Protects all data in transit between instances — federation metadata, public channel messages, authentication headers, and API calls. This is what `FORCE_SSL` controls.
- **End-to-end encryption (E2EE):** Protects message content in private and voice channels using MLS/Double Ratchet. E2EE works regardless of transport — even over HTTP, message content in private channels is encrypted client-to-client.

An instance is considered **secure** if it uses HTTPS, and **insecure** if it uses plain HTTP. The well-known federation endpoint advertises each instance's security status so other nodes can make informed policy decisions.

## Insecure federation

By default, Cairn only federates with HTTPS instances. To allow federation with HTTP-only nodes (for example, instances on private networks or IP addresses without TLS), enable `FEDERATION_ALLOW_INSECURE`:

```sh
cairn-ctl federation allow-insecure true
cairn-ctl restart
```

Or set it in `.env`:

```env
FEDERATION_ALLOW_INSECURE=true
```

### What "insecure" means

When federating with an HTTP-only instance, the following data is sent in plain text over the network and can be intercepted by anyone on the network path:

- Federation metadata (node IDs, public keys, handshake messages)
- Public channel messages and edits
- ActivityPub activity payloads (author info, timestamps)
- HTTP Signature headers (though signatures themselves prevent tampering)

### What remains protected

- **Private and voice channel content** — these channels use E2EE (MLS key agreement + AES-128-GCM), so message content is encrypted client-to-client regardless of transport.
- **DMs** — never federated at all; they stay on the sender's home instance.
- **User passwords** — only sent between the user's client and their own home instance, not between instances.

### Restrictions on insecure nodes

Even with `FEDERATION_ALLOW_INSECURE=true`, insecure nodes face restrictions:

- **Blocked from E2EE channels.** Messages from insecure nodes are rejected for private and voice channels. This prevents metadata leakage (who is sending, when, to which channel) over unencrypted transport.
- **Visible warnings.** Users on insecure instances and users interacting with insecure peers see clear warnings (see below).

### HTTPS-first handshake

When initiating federation with a new remote instance, Cairn always tries HTTPS first. HTTP is only attempted as a fallback if HTTPS fails and `FEDERATION_ALLOW_INSECURE` is enabled. If `FEDERATION_ALLOW_INSECURE` is `false` (the default), HTTP-only nodes are rejected.

The transport security status of each node is recorded and used for all subsequent communication.

### User-facing warnings

Cairn shows clear warnings so users understand the security implications:

**On insecure instances (HTTP):**
A persistent red banner appears at the top of the app:

> This server is not using HTTPS. Your connection is not encrypted. Passwords, messages, and files are sent in plain text.

This banner is shown on all pages, including login and registration. Users can dismiss it, but it reappears on each page load.

**When interacting with insecure federated users:**
- Federated members from insecure instances show an unlocked-shield icon next to their federation badge in the member list.
- When sending a DM request to a user on an insecure instance, a warning is shown:

> This user's server does not use HTTPS. DM request metadata will be sent over an unencrypted connection.

### When to use insecure federation

Insecure federation is appropriate for:

- **Private/home networks** — instances on a LAN or VPN where network traffic is already trusted
- **Development and testing** — local instances without TLS certificates
- **IP-only deployments** — servers without a domain name where Let's Encrypt isn't an option

It is **not recommended** for public-facing instances accessible over the internet.

## How it works

### Discovery

Each federated instance publishes a well-known endpoint at:

```
https://cairn.example.com/.well-known/cairn-federation
```

This returns the instance's public Ed25519 signing key, protocol version, inbox URL, privacy manifest, and transport security status (`secure: true/false`).

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

This shows all remote instances your server has communicated with, their current status, and whether they use a secure (HTTPS) or insecure (HTTP) connection.

Check or change the insecure federation policy:

```sh
cairn-ctl federation allow-insecure         # show current value
cairn-ctl federation allow-insecure true    # allow HTTP peers
cairn-ctl federation allow-insecure false   # require HTTPS peers
```

After changing the policy, restart services:

```sh
cairn-ctl restart
```

## Rate limiting

Inbound federation requests are rate-limited to prevent abuse. The server applies per-instance limits on incoming ActivityPub deliveries.

## Disabling federation

```sh
cairn-ctl config FEDERATION_ENABLED false
cairn-ctl restart
```

Existing federated data (remote users, memberships) will remain in the database but no new federation activity will occur.
