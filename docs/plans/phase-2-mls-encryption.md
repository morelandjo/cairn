# Phase 2: MLS Group Encryption + Private Channels

**Duration:** 6-8 weeks
**Goal:** Implement MLS (RFC 9420) for group E2E encryption, then unlock private channels as a feature. This is the crypto-heavy phase that fulfills the core promise of mandatory E2E encryption for group conversations.
**Dependencies:** Phase 1 complete (user auth, Ed25519 identity keys, DM encryption working, public channels working)
**Deliverable:** Private channels with MLS-based E2E encryption. Encrypted key backup for account recovery.

---

## Review Issues Addressed

- **#1 — Private channel encryption gap:** RESOLVED — private channels only ship after MLS is implemented
- **#2 — Account recovery (key backup):** Encrypted key backup with passphrase-derived encryption

---

## Why This Phase Exists

The original design deferred MLS to Phase 6 (late hardening). This meant private channels would have existed without E2E encryption for months of development — contradicting the core privacy promise. By pulling MLS into Phase 2:

1. Private channels are never shipped without encryption
2. E2E voice in Phase 5 can use MLS keys (already available)
3. The hardest crypto work is done early, reducing late-stage risk

---

## Tasks

### MLS Library Selection & Setup

- [ ] **2.1** Evaluate MLS implementations:
  - **openmls** (Rust, open source) — mature, well-tested, compiles to WASM
  - **mls-rs** (AWS Labs, Rust) — newer, designed for WASM from the start
  - Selection criteria: WASM bundle size, API ergonomics, RFC 9420 compliance, active maintenance, documentation quality
  - Produce a short evaluation document in `docs/decisions/mls-library.md`

- [ ] **2.2** Set up Rust → WASM build pipeline in `proto/`:
  - `proto/mls-wasm/` — Rust crate that wraps chosen MLS library
  - Build via `wasm-pack build --target web` (or `wasm-bindgen`)
  - Output: `.wasm` file + TypeScript bindings
  - Integrate into `proto/` TypeScript package as a dependency
  - CI step: build WASM on every push, cache Rust target directory

- [ ] **2.3** Integrate MLS WASM module into shared crypto library:
  - `proto/src/mls.ts` — TypeScript wrapper around WASM bindings
  - Export: `createGroup()`, `addMember()`, `removeMember()`, `encryptMessage()`, `decryptMessage()`, `generateKeyPackage()`, `processWelcome()`, `processCommit()`
  - Handle WASM initialization (async load, memory management)
  - Error handling: meaningful error types for common failures

### MLS Credential & Key Management

- [ ] **2.4** MLS credential from existing identity:
  - Each user's Ed25519 identity key (generated in Phase 1) serves as their MLS BasicCredential
  - Mapping: `IdentityKey → MLS Credential → MLS LeafNode`
  - No new key types needed — reuse existing PKI

- [ ] **2.5** KeyPackage generation:
  - Client generates MLS KeyPackages (pre-computed join tokens)
  - Each KeyPackage is single-use (like one-time prekeys in X3DH)
  - Client uploads batch of 50 KeyPackages to server on key setup and periodically replenishes

- [ ] **2.6** Server KeyPackage endpoints:
  - `POST /api/v1/users/me/key-packages` — upload batch of KeyPackages
  - `GET /api/v1/users/:id/key-packages` — claim one KeyPackage (consumed on retrieval, removed from server)
  - `GET /api/v1/users/me/key-packages/count` — check remaining KeyPackages (client replenishes when low)
  - Server stores KeyPackages as opaque blobs (cannot inspect contents)

### MLS Group Operations

- [ ] **2.7** Group creation:
  - When a user creates a private channel, the client:
    1. Creates a new MLS group (with its own credential as the first member)
    2. Sends the GroupInfo to the server for storage
  - Server endpoint: `POST /api/v1/channels/:id/mls/group-info` — store initial group state
  - Group ID maps 1:1 to channel ID

- [ ] **2.8** Server MLS delivery service:
  - `POST /api/v1/channels/:id/mls/commit` — submit MLS Commit messages (group state changes)
  - `POST /api/v1/channels/:id/mls/proposal` — submit MLS Proposals (pending changes)
  - `POST /api/v1/channels/:id/mls/welcome` — submit Welcome messages for new members
  - `GET /api/v1/channels/:id/mls/messages` — fetch pending MLS handshake messages for the requesting user
  - All MLS protocol messages stored as opaque blobs — server is a dumb relay

- [ ] **2.9** Member Add flow:
  1. Inviter fetches invitee's KeyPackage from server
  2. Inviter creates MLS Add Proposal + Commit locally
  3. Inviter submits Commit to server
  4. Server distributes Welcome message to new member
  5. Server distributes Commit to all existing members
  6. All members update their local group state (new epoch)
  7. New member processes Welcome → gains access to group from this point forward

- [ ] **2.10** Member Remove flow:
  1. Authorized user (channel owner/moderator or self-leave) creates Remove Proposal + Commit
  2. Submit Commit to server
  3. Server distributes Commit to remaining members
  4. Remaining members update group state → new epoch key
  5. Removed member's client deletes local group state
  6. **Forward secrecy:** removed member cannot decrypt messages sent after removal

- [ ] **2.11** Application message encryption:
  - Channel messages encrypted with current MLS epoch's application secret
  - Message format: MLS MLSCiphertext (includes epoch, content type, encrypted payload)
  - Server stores ciphertext — cannot decrypt
  - Recipients decrypt using their local MLS group state

- [ ] **2.12** Epoch management:
  - Each Add/Remove/Update advances the epoch counter
  - Clients track current epoch and retain keys for recent epochs (configurable, default: last 10 epochs)
  - Messages include epoch number → client selects correct decryption key
  - Old epoch keys are eventually deleted (forward secrecy for old messages against future key compromise)

- [ ] **2.13** Out-of-order MLS message handling:
  - Buffer incoming Proposals until corresponding Commit arrives
  - Handle Commits that reference unknown Proposals (fetch from server)
  - Timeout: if Commit doesn't arrive within 60 seconds, request resync
  - Conflict resolution: if two Commits for same epoch arrive, accept the one the server processed first

### Private Channels (Unlocked by MLS)

- [ ] **2.14** Add `private` channel type:
  - Database migration: add `private` to channel type enum
  - Server validation: `private` channels require MLS group to be established
  - Permission: only channel creator can initially invite members

- [ ] **2.15** Private channel creation flow:
  - `POST /api/v1/channels` with `{ "type": "private", "name": "...", "members": [...] }`
  - Server creates channel record
  - Server responds with channel ID
  - Client creates MLS group → invites initial members → uploads group state
  - Channel becomes active once MLS handshake completes

- [ ] **2.16** Invite to private channel:
  - Owner/moderator invites user → triggers MLS Add flow (task 2.9)
  - New member receives Welcome → can read messages from this point forward
  - **No access to message history before joining** (by design — forward secrecy)

- [ ] **2.17** Leave private channel:
  - User sends leave request → triggers MLS Remove flow (task 2.10)
  - Group key updates → departed member loses access to future messages
  - Channel member list updated

- [ ] **2.18** Private channel message flow:
  1. Sender composes message
  2. Client encrypts via MLS (`encryptMessage()`)
  3. Send via WebSocket: `{ encrypted_content: <ciphertext>, mls_epoch: <n> }`
  4. Server persists ciphertext + epoch (cannot read content)
  5. Server broadcasts to channel members
  6. Recipients decrypt with MLS group state
  7. Display plaintext to user

### Encrypted Key Backup

- [ ] **2.19** Key export format:
  - Export: identity private key, signed prekey private, all one-time prekey privates, MLS group states (serialized), Double Ratchet sessions
  - Serialize to a single binary blob
  - Encrypt with AES-256-GCM, key derived from user passphrase via Argon2id (high memory cost: 256MB, 3 iterations)

- [ ] **2.20** Server backup endpoints:
  - `POST /api/v1/users/me/key-backup` — upload encrypted backup blob (max 10MB)
  - `GET /api/v1/users/me/key-backup` — retrieve encrypted backup
  - `DELETE /api/v1/users/me/key-backup` — delete backup
  - Server stores as opaque blob — cannot decrypt without user's passphrase

- [ ] **2.21** Key backup flow:
  1. User goes to Settings → Security → Key Backup
  2. Prompted to create a strong backup passphrase (separate from account password)
  3. Client exports all private keys + crypto state
  4. Client derives encryption key from passphrase (Argon2id)
  5. Client encrypts export blob
  6. Client uploads to server
  7. Confirmation: "Your keys are backed up. You will need your backup passphrase to restore."

- [ ] **2.22** Key restore flow:
  1. User logs in on new device (or after key loss)
  2. Prompted: "Restore encrypted keys from backup?"
  3. User enters backup passphrase
  4. Client downloads encrypted backup from server
  5. Client derives key from passphrase, decrypts
  6. Client restores all private keys + crypto state
  7. Client can now decrypt DMs and rejoin MLS groups

- [ ] **2.23** Cross-device key sync via QR code:
  - Existing device displays QR code containing: temporary encryption key + server URL
  - New device scans QR code
  - Existing device encrypts key export with temporary key, uploads to server (ephemeral, 5-minute TTL)
  - New device downloads + decrypts
  - Faster than passphrase backup for adding a second device

### Web Client Updates

- [ ] **2.24** Private channel creation UI:
  - "Create Channel" dialog: option to select "Private (E2E Encrypted)"
  - Member selector: search and add users to invite
  - Encryption indicator: shield/lock icon on private channels
  - Loading state: "Setting up encryption..." during MLS group creation

- [ ] **2.25** MLS group management UI:
  - Channel settings → Members panel
  - Invite new members (triggers MLS Add)
  - Remove members (triggers MLS Remove, requires moderator/owner)
  - Leave channel button (triggers self-Remove)
  - Member list with encryption status indicators

- [ ] **2.26** Encrypted message rendering:
  - Decrypt-on-display: messages decrypted when scrolled into view (or batch on channel open)
  - Loading state: skeleton/shimmer while decrypting
  - Error state: "Unable to decrypt message" (epoch key missing, corrupted, etc.)
  - Performance: decrypt in Web Worker to avoid blocking UI thread

- [ ] **2.27** Key backup/restore UI:
  - Settings → Security → Key Backup
  - Backup: passphrase input (with strength meter), "Back Up Keys" button, success confirmation
  - Restore: passphrase input, "Restore Keys" button, progress indicator, success/failure feedback
  - QR sync: "Add New Device" → display QR code → "Waiting for new device..."

- [ ] **2.28** Key health indicators:
  - Settings → Security shows:
    - Number of KeyPackages remaining on server
    - Last key backup date
    - Number of active MLS group sessions
    - "Replenish KeyPackages" action when count is low

---

## Testing Checkpoint

- [ ] Create private channel with 3 members, send messages:
  - All 3 members can read all messages
  - Server database contains only ciphertext
  - Verify MLS epoch advances on member changes
- [ ] Add a 4th member to existing private channel:
  - 4th member can read NEW messages
  - 4th member CANNOT read messages from before they joined
- [ ] Remove a member from private channel:
  - Removed member cannot read NEW messages
  - Remaining members' group key has rotated
- [ ] Key backup round-trip:
  - Export keys → delete local keys → restore from backup → verify all encrypted content is still accessible
- [ ] QR code key sync:
  - Open second browser/incognito → scan QR → verify keys transferred → verify encrypted content accessible
- [ ] Scalability test: private channel with 50+ members
  - MLS operations complete within acceptable time (<2s for group operations)
  - Message encrypt/decrypt remains fast (<50ms per message)
- [ ] Edge cases:
  - Simultaneous Add proposals from two different members
  - Network disconnect during Commit delivery → reconnect → state recovery
  - KeyPackage exhaustion → graceful error → replenishment prompt

---

## Notes

- This is the highest technical risk phase. MLS + WASM is bleeding edge. Budget extra time.
- If the chosen MLS library has showstopper issues in WASM, fallback plan: use Sender Keys (like Signal groups) instead of full MLS. Less elegant but functional. Document the tradeoff.
- MLS ciphersuites: use `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` (mandatory-to-implement per RFC 9420).
- The 10-epoch key retention window is a tradeoff between forward secrecy and usability. Can be tuned later.
- Cross-device sync via QR is a nice-to-have for this phase. Passphrase backup is the priority.
