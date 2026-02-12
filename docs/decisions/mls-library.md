# ADR: MLS Library Selection

**Status:** Accepted
**Date:** 2026-02-09
**Context:** Phase 2 — MLS Group Encryption for Private Channels

## Decision

Use **openmls 0.8.0** compiled to WASM via `wasm-bindgen` for MLS (RFC 9420) group encryption.

## Context

Cairn needs group end-to-end encryption for private channels. The MLS protocol (RFC 9420) is the IETF standard for scalable group key agreement. We need an implementation that:

1. Runs in the browser (WASM)
2. Is RFC 9420 compliant
3. Has production usage evidence
4. Works with our existing Ed25519 identity keys

## Options Considered

| Library | Language | RFC 9420 | WASM | Production Use |
|---------|----------|----------|------|----------------|
| openmls | Rust | Yes | Yes (`js` feature) | Wire messenger |
| mls-rs (AWS) | Rust | Yes | Untested | Internal AWS |
| Custom TS impl | TypeScript | Partial | N/A | None |

## Rationale

- **openmls** is battle-tested in Wire messenger, the most prominent MLS deployment
- The `js` feature flag enables `getrandom` JS backend for WASM builds
- `openmls_rust_crypto` provides a pure-Rust crypto backend (RustCrypto), avoiding C dependencies that complicate WASM compilation
- Ed25519 credentials are supported via the mandatory `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` ciphersuite, which uses the same curve as our existing identity keys
- `mls-rs` (AWS) lacks documented WASM support and production deployment evidence
- A custom TypeScript implementation would be extremely high risk for a complex protocol

## Architecture

- **Crate location:** `proto/mls-wasm/` — co-located with the proto package that consumes it
- **WASM target:** `--target web` (ES module) via `wasm-bindgen`
- **Crypto provider:** `openmls_rust_crypto` (pure Rust, no C deps)
- **Ciphersuite:** `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`
- **State model:** All MLS state serialized to bytes, managed by TypeScript — no hidden WASM-side state

## Consequences

- Adds Rust toolchain requirement to development and CI
- WASM binary adds ~1-2MB to client bundle (gzipped)
- openmls API changes between minor versions may require migration work
- Server remains untrusted — stores only opaque binary blobs
