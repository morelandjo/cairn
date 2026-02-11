# Frequently Asked Questions

## 1. Do I need to register a user every time I want to add a new server?

**No.** Your Murmuring identity is portable across instances:

- **Joining a new server (guild) on the same instance** — Your account works across all servers within the same Murmuring instance. Just join via an invite link, invite code, or the server discovery directory. One account, unlimited servers.

- **Joining a server on a different Murmuring instance** — You do **not** need to create a new account. Murmuring uses a portable cryptographic identity system (`did:murmuring`) that lets you join servers on any federated instance using your existing account. Your home instance issues a signed authentication token that the remote instance verifies, so you can participate in remote servers without re-registering.

Your identity is a self-certifying decentralized identifier (DID) derived from your cryptographic keys. It stays the same even if you rotate your keys or change your username. In the client, remote servers appear grouped by instance in the sidebar, and your messages show your `username@home-instance` to other users.

## 2. What happens if my signing key is compromised?

Murmuring uses two separate key pairs: a **signing key** for daily use (E2EE, message signing) and a **rotation key** used only for identity operations. If your signing key is compromised:

1. Use the **Rotate Signing Key** button in Security Settings
2. Your rotation key signs a new operation in your DID's hash-chained operation log
3. Your DID stays the same — only the active signing key changes
4. The old key is immediately rejected for new operations

If your rotation key is also compromised, use your **recovery codes** to rotate the rotation key itself. This is the last line of defense.

## 3. How does federation work with portable identity?

When you join a server on a remote instance:

1. Your home instance issues a time-limited, node-signed authentication token
2. The remote instance verifies the token against your home instance's known Ed25519 key
3. The remote instance fetches and verifies your DID operation chain (anti-impersonation)
4. Your client establishes a WebSocket connection directly to the remote instance
5. You participate in real-time, just like a local user

Cross-instance DMs are supported — see [Q5](#5-can-i-dm-users-on-other-instances) for details. The DM channel lives on the initiator's instance; the recipient connects via federated auth.

## 4. What if my home instance is compromised or deleted?

**Compromised (attacker gains server access):**

- Your **E2EE message content is safe** — the server only ever stores ciphertext. The attacker can read metadata (who messaged whom, when, which channels) but not the content of private channels or DMs.
- The attacker **cannot forge your DID identity** — DID operations require your rotation key, which is stored on your device (and in your client-encrypted key backup), not on the server. The operation chain is signed, so any tampering is detectable by remote instances.
- The attacker **could issue federated auth tokens** on your behalf (since they control the node's Ed25519 key). Remote instances you're connected to should be notified. The compromised instance should be defederated by peers.
- Your **local key material is unaffected** — your signing key, rotation key, and MLS group states live on your device.

**Deleted (instance goes offline permanently):**

- Your **DID still exists** — it's derived from your cryptographic keys, not from the instance. Remote instances that have cached your DID operation chain can still verify your identity independently.
- Your **DMs you initiated are lost** — DM channels you created live on your home instance. If you have an encrypted key backup and the database is recoverable, the operator may be able to restore them. Otherwise, they are gone. DMs initiated by others (where you were the recipient) live on the initiator's instance and are unaffected.
- Your **remote server memberships continue to work** as long as the remote instances have your federated user record cached. However, you cannot obtain new federated auth tokens without a home instance, so you cannot join additional remote servers.
- **To recover fully**, you would register on a new home instance and use your existing key material to create a new DID. Your old remote memberships would need to be re-established. Full instance migration (transferring your DID to a new home instance via an operation chain entry) is a planned future enhancement.

## 5. Can I DM users on other instances?

**Yes.** Murmuring supports cross-instance encrypted DMs using an "initiator hosts" model:

1. **You initiate the DM** from a shared server's member list (click "DM" on a federated user's profile)
2. Your client fetches the recipient's X3DH key bundle from their home instance (via federation)
3. A DM channel is created **on your instance only** — messages are never replicated to the recipient's instance
4. The recipient receives a **DM request notification** (a lightweight "DM hint" delivered via federation)
5. The recipient **accepts or rejects** the request. If accepted, they connect to your instance via federated auth token + WebSocket
6. Both sides exchange E2E encrypted messages (X3DH + Double Ratchet) — your instance only sees ciphertext

**Key privacy properties:**
- DM **messages** are never federated via ActivityPub — only the DM hint (sender DID, channel ID) crosses instances
- The hosting instance (initiator's) only stores ciphertext — it cannot read message content
- The recipient's home instance learns nothing about the DM conversation after the initial hint
- Recipients must explicitly accept DM requests before any messages can be exchanged
- Rate limiting (10 requests/hour) and block lists prevent DM spam

**Anti-spam protections:**
- Max 10 DM requests per hour per user
- Max 5 pending requests per recipient
- Recipients can reject and **block** a sender's DID to prevent future requests

## 6. What happens if I disable federation?

Disabling federation gives you a **fully self-contained private server** — think of it like running your own private Discord. Everything works within your instance, but nothing connects to the outside world.

**What you keep:**
- All messaging, channels, servers, roles, and permissions
- Direct messages between users on your instance
- End-to-end encryption for private channels and DMs
- Voice and video calls
- Search, moderation tools, bots, webhooks, file uploads
- Custom emoji, notifications, data export

**What you give up:**
- Users from other Murmuring instances cannot join your servers
- Your users cannot join servers on other instances
- Cross-instance DMs are not available
- Your instance won't appear in any federated discovery or exchanges

This is the right choice for a **personal or small group server** where everyone has an account on the same instance and there's no need to interact with the broader Murmuring network. You can always enable federation later if your needs change — it's a configuration toggle, not a one-way decision.

## 7. Can I run Murmuring without a domain name?

**Yes**, when federation is disabled. Murmuring supports three deployment modes:

1. **Domain + reverse proxy + TLS** (recommended) — standard production setup with a domain name and TLS certificate.
2. **IP + tunnel** (Tailscale, Cloudflare Tunnel) — the server is accessible via a VPN or tunnel that provides transport encryption. You can use a bare IP address.
3. **IP + no SSL** (LAN only) — for home networks or Raspberry Pi setups. Set `FORCE_SSL=false` in your `.env`. Clients will show a security warning when connecting over HTTP.

**Important constraints:**
- Federation **requires** a domain name and TLS. If you enable federation, SSL enforcement is automatically enabled regardless of the `FORCE_SSL` setting.
- When connecting to a server over plain HTTP, both the web and mobile clients display an "Insecure Connection" warning. Users must explicitly confirm before proceeding.
- Only use HTTP on networks you fully trust (home LAN, Tailscale mesh, etc.). On untrusted networks, credentials and messages could be intercepted.

See the [Server Guide — TLS Modes](SERVER.md#tls-modes) for details
