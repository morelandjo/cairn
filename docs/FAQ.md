# Frequently Asked Questions

## 1. What is federation?

Think of it like the United Federation of Planets in Star Trek. Each planet (Cairn instance) is independently governed — it has its own captain, its own crew, its own rules. But because they're all part of the Federation, a crew member from Earth can visit Deep Space Nine, talk to people on Vulcan, and send subspace messages across the quadrant — all without needing to apply for citizenship on every planet they visit.

That's how Cairn federation works:

- **Each instance is a planet.** You run your own server, you make the rules, you control your data. Nobody else can tell you what to do on your instance.
- **Your identity is your communicator badge.** When you register on your home instance, you get a cryptographic identity (`did:cairn`) that proves who you are everywhere. It's like a Starfleet ID — any allied planet can verify it.
- **Visiting other instances is like visiting other planets.** You can join servers on remote instances without creating a new account. Your home instance vouches for you (issues a signed token), and the remote instance lets you in.
- **Messages stay encrypted in transit.** Just like subspace communications, your messages are end-to-end encrypted. The servers carrying them can't read the contents — they just route them.
- **You can go solo.** Don't want to join the Federation? Disable it and run a fully self-contained private server. You're the Romulan Empire — totally independent, everything works internally, you just don't talk to the outside.

The technical details: federation uses ActivityPub for activity delivery, HTTP Signatures (RFC 9421) for authentication between instances, and hash-chained DID operation logs for tamper-proof portable identity. But you don't need to know any of that — just enable it in the installer and it works.

## 2. Do I need to register a user every time I want to add a new server?

**No.** Your Cairn identity is portable across instances:

- **Joining a new server (guild) on the same instance** — Your account works across all servers within the same Cairn instance. Just join via an invite link, invite code, or the server discovery directory. One account, unlimited servers.

- **Joining a server on a different Cairn instance** — You do **not** need to create a new account. Cairn uses a portable cryptographic identity system (`did:cairn`) that lets you join servers on any federated instance using your existing account. Your home instance issues a signed authentication token that the remote instance verifies, so you can participate in remote servers without re-registering.

Your identity is a self-certifying decentralized identifier (DID) derived from your cryptographic keys. It stays the same even if you rotate your keys or change your username. In the client, remote servers appear grouped by instance in the sidebar, and your messages show your `username@home-instance` to other users.

## 3. What happens if my signing key is compromised?

Cairn uses two separate key pairs: a **signing key** for daily use (E2EE, message signing) and a **rotation key** used only for identity operations. If your signing key is compromised:

1. Use the **Rotate Signing Key** button in Security Settings
2. Your rotation key signs a new operation in your DID's hash-chained operation log
3. Your DID stays the same — only the active signing key changes
4. The old key is immediately rejected for new operations

If your rotation key is also compromised, use your **recovery codes** to rotate the rotation key itself. This is the last line of defense.

## 4. How does federation work with portable identity?

When you join a server on a remote instance:

1. Your home instance issues a time-limited, node-signed authentication token
2. The remote instance verifies the token against your home instance's known Ed25519 key
3. The remote instance fetches and verifies your DID operation chain (anti-impersonation)
4. Your client establishes a WebSocket connection directly to the remote instance
5. You participate in real-time, just like a local user

Cross-instance DMs are supported — see [Q6](#6-can-i-dm-users-on-other-instances) for details. The DM channel lives on the initiator's instance; the recipient connects via federated auth.

## 5. What if my home instance is compromised or deleted?

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

## 6. Can I DM users on other instances?

**Yes.** Cairn supports cross-instance encrypted DMs using an "initiator hosts" model:

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

## 7. What happens if I disable federation?

Disabling federation gives you a **fully self-contained private server** — think of it like running your own private Discord. Everything works within your instance, but nothing connects to the outside world.

**What you keep:**
- All messaging, channels, servers, roles, and permissions
- Direct messages between users on your instance
- End-to-end encryption for private channels and DMs
- Voice and video calls
- Search, moderation tools, bots, webhooks, file uploads
- Custom emoji, notifications, data export

**What you give up:**
- Users from other Cairn instances cannot join your servers
- Your users cannot join servers on other instances
- Cross-instance DMs are not available
- Your instance won't appear in any federated discovery or exchanges

This is the right choice for a **personal or small group server** where everyone has an account on the same instance and there's no need to interact with the broader Cairn network. You can always enable federation later if your needs change — it's a configuration toggle, not a one-way decision.

## 8. Can I run Cairn without a domain name?

**Yes**, when federation is disabled. Cairn supports three deployment modes:

1. **Domain + reverse proxy + TLS** (recommended) — standard production setup with a domain name and TLS certificate.
2. **IP + tunnel** (Tailscale, Cloudflare Tunnel) — the server is accessible via a VPN or tunnel that provides transport encryption. You can use a bare IP address.
3. **IP + no SSL** (LAN only) — for home networks or Raspberry Pi setups. Set `FORCE_SSL=false` in your `.env`. Clients will show a security warning when connecting over HTTP.

**Important constraints:**
- Federation **requires** a domain name and TLS. If you enable federation, SSL enforcement is automatically enabled regardless of the `FORCE_SSL` setting.
- When connecting to a server over plain HTTP, both the web and mobile clients display an "Insecure Connection" warning. Users must explicitly confirm before proceeding.
- Only use HTTP on networks you fully trust (home LAN, Tailscale mesh, etc.). On untrusted networks, credentials and messages could be intercepted.

See the [Server Guide — TLS Modes](SERVER.md#tls-modes) for details

## 9. What if someone steals the entire database?

If a bad actor gets a full dump of the PostgreSQL database, here's what they get and what they don't.

**What they CAN read (plaintext or lightly obfuscated):**

- **User accounts** — usernames, email addresses, password hashes (Argon2, so cracking is expensive but theoretically possible for weak passwords)
- **Membership** — who is in which server, which channels, what roles they have
- **Server/channel structure** — server names, channel names, categories, role names, permission settings
- **Public channel messages** — content posted in channels marked as public is stored in plaintext (the user chose to make it public)
- **Meilisearch index data** — a copy of public channel content (only public channels are indexed)
- **Message metadata** — timestamps, author IDs, channel IDs, message IDs, edit history for all messages (public, private, and DMs)
- **File metadata** — filenames, sizes, MIME types, upload timestamps, which channel they were posted in
- **Federation state** — which instances are federated, node public keys, federated user records (DIDs, actor URIs, display names)
- **DID operation logs** — the full hash-chained operation history (but this is public by design — anyone can verify it)
- **Audit logs** — records of logins, moderation actions, role changes, federation events
- **Oban job queue** — pending background jobs (federation deliveries, push notification metadata)
- **Session tokens in Redis** — if they also compromise Redis, active session tokens (JWTs are short-lived, but refresh tokens could allow session hijack until rotated)

**What they CANNOT read (encrypted, keys not on the server):**

- **Private channel messages** — stored as MLS ciphertext. The server never had the decryption keys; they live in clients' MLS group state. The attacker gets meaningless binary blobs.
- **DM messages** — stored as Double Ratchet ciphertext. Same story — the server only ever stored opaque encrypted payloads.
- **Voice/video content** — not stored at all. Voice frames are transient, encrypted in flight with AES-128-GCM, and never hit the database.
- **Key backups** — encrypted with the user's passphrase via Argon2id (256 MB memory, 3 iterations) + XChaCha20-Poly1305. Without the passphrase, the backup is a blob. The high Argon2id memory parameter makes brute-forcing impractical even with dedicated hardware.
- **MLS group state** — the server stores MLS key packages, welcome messages, and commits as opaque binary blobs. It cannot reconstruct group keys from these.
- **User signing keys and rotation keys** — these live on client devices (or in the encrypted key backup). They are never sent to the server in plaintext.
- **Encrypted file contents** — files uploaded in private channels are encrypted client-side. The decryption key is embedded in the MLS-encrypted message. The server has the encrypted file and the encrypted message, but cannot connect the key to the file.

**The practical summary:**

A database dump reveals *who talked to whom, when, and in which channels* — but for private channels and DMs, the actual message content is indistinguishable from random bytes. Public channel content is readable because the user chose to post publicly. The attacker learns the social graph and metadata, but not the substance of private conversations.

This is by design. The [Untrusted Server Model](DESIGN.md#4-the-untrusted-server-model) means the server never possesses the keys needed to decrypt private content, so stealing the database gives the attacker exactly what the server itself could see — and no more.
