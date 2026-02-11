/**
 * DID (Decentralized Identifier) operations for did:murmuring method.
 *
 * Provides client-side creation/verification of the self-certifying
 * DID operation chain. Uses libsodium for Ed25519 signing/verification.
 */

import { ensureSodium } from "./keys.js";
import type { DIDOperation } from "../types.js";

// ─── Base58 (Bitcoin alphabet) ───

const BASE58_ALPHABET =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

export function base58Encode(bytes: Uint8Array): string {
  // Count leading zeros
  let leadingZeros = 0;
  for (const b of bytes) {
    if (b !== 0) break;
    leadingZeros++;
  }

  // Convert bytes to BigInt
  let num = BigInt(0);
  for (const b of bytes) {
    num = num * BigInt(256) + BigInt(b);
  }

  // Encode to base58
  let encoded = "";
  while (num > BigInt(0)) {
    const rem = Number(num % BigInt(58));
    encoded = BASE58_ALPHABET[rem] + encoded;
    num = num / BigInt(58);
  }

  return "1".repeat(leadingZeros) + encoded;
}

export function base58Decode(str: string): Uint8Array {
  // Count leading '1's
  let leadingOnes = 0;
  for (const c of str) {
    if (c !== "1") break;
    leadingOnes++;
  }

  // Decode base58 to BigInt
  let num = BigInt(0);
  for (const c of str) {
    const idx = BASE58_ALPHABET.indexOf(c);
    if (idx === -1) throw new Error(`Invalid base58 character: ${c}`);
    num = num * BigInt(58) + BigInt(idx);
  }

  // Convert BigInt to bytes
  const hexStr = num === BigInt(0) ? "" : num.toString(16);
  const paddedHex = hexStr.length % 2 === 0 ? hexStr : "0" + hexStr;
  const dataBytes = new Uint8Array(
    (paddedHex.match(/.{2}/g) || []).map((b) => parseInt(b, 16)),
  );

  // Prepend zero bytes for leading '1's
  const result = new Uint8Array(leadingOnes + dataBytes.length);
  result.set(dataBytes, leadingOnes);
  return result;
}

// ─── Multibase ───

export function multibaseEncode(bytes: Uint8Array): string {
  return "z" + base58Encode(bytes);
}

export function multibaseDecode(encoded: string): Uint8Array {
  if (!encoded.startsWith("z")) {
    throw new Error("Unsupported multibase encoding (expected base58btc 'z' prefix)");
  }
  return base58Decode(encoded.slice(1));
}

// ─── Canonical JSON ───

function sortKeys(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      sorted[key] = sortKeys((value as Record<string, unknown>)[key]);
    }
    return sorted;
  }
  return value;
}

export function canonicalJson(payload: Record<string, unknown>): string {
  return JSON.stringify(sortKeys(payload));
}

// ─── DID Operations ───

export interface GenesisResult {
  did: string;
  operation: {
    payload: Record<string, unknown>;
    signature: Uint8Array;
  };
}

/**
 * Create a genesis operation for a new DID.
 *
 * @param signingPublicKey - Ed25519 signing public key (32 bytes)
 * @param rotationKeyPair - Ed25519 rotation key pair (for signing the genesis)
 * @param handle - Username/handle
 * @param service - Home instance domain
 */
export async function createGenesisOperation(
  signingPublicKey: Uint8Array,
  rotationKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array },
  handle: string,
  service: string,
): Promise<GenesisResult> {
  const s = await ensureSodium();

  const payload: Record<string, unknown> = {
    type: "create",
    signingKey: multibaseEncode(signingPublicKey),
    rotationKey: multibaseEncode(rotationKeyPair.publicKey),
    handle,
    service,
    prev: null,
  };

  const canonical = canonicalJson(payload);
  const signature = s.crypto_sign_detached(
    s.from_string(canonical),
    rotationKeyPair.privateKey,
  );

  // DID = did:murmuring:<base58(SHA-256(canonical + signature))>
  const signedData = new Uint8Array(
    s.from_string(canonical).length + signature.length,
  );
  signedData.set(s.from_string(canonical));
  signedData.set(signature, s.from_string(canonical).length);

  const hash = await crypto.subtle.digest("SHA-256", signedData);
  const did = "did:murmuring:" + base58Encode(new Uint8Array(hash));

  return { did, operation: { payload, signature } };
}

/**
 * Sign a DID operation with the rotation private key.
 */
export async function signOperation(
  payload: Record<string, unknown>,
  rotationPrivateKey: Uint8Array,
): Promise<Uint8Array> {
  const s = await ensureSodium();
  const canonical = canonicalJson(payload);
  return s.crypto_sign_detached(s.from_string(canonical), rotationPrivateKey);
}

/**
 * Compute the SHA-256 hash of a signed operation (for chain linking).
 */
export async function hashOperation(
  payload: Record<string, unknown>,
  signature: Uint8Array,
): Promise<string> {
  const s = await ensureSodium();
  const canonical = canonicalJson(payload);
  const canonicalBytes = s.from_string(canonical);

  const signedData = new Uint8Array(canonicalBytes.length + signature.length);
  signedData.set(canonicalBytes);
  signedData.set(signature, canonicalBytes.length);

  const hash = await crypto.subtle.digest("SHA-256", signedData);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Compute a DID from a genesis operation (for verification).
 */
export async function computeDid(
  payload: Record<string, unknown>,
  signature: Uint8Array,
): Promise<string> {
  const s = await ensureSodium();
  const canonical = canonicalJson(payload);
  const canonicalBytes = s.from_string(canonical);

  const signedData = new Uint8Array(canonicalBytes.length + signature.length);
  signedData.set(canonicalBytes);
  signedData.set(signature, canonicalBytes.length);

  const hash = await crypto.subtle.digest("SHA-256", signedData);
  return "did:murmuring:" + base58Encode(new Uint8Array(hash));
}

/**
 * Decode a base64 string to Uint8Array.
 */
function fromBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Verify the integrity of an operation chain.
 *
 * Checks:
 * 1. Genesis has prev: null and seq: 0
 * 2. Hash chain links are correct
 * 3. All signatures are valid
 * 4. DID derivation from genesis matches
 */
export async function verifyOperationChain(
  did: string,
  operations: DIDOperation[],
): Promise<{ valid: boolean; error?: string }> {
  const s = await ensureSodium();

  if (operations.length === 0) {
    return { valid: false, error: "empty chain" };
  }

  const genesis = operations[0]!;

  // Verify genesis
  if (genesis.seq !== 0 || genesis.prev_hash !== null) {
    return { valid: false, error: "invalid genesis" };
  }
  if (genesis.operation_type !== "create") {
    return { valid: false, error: "genesis must be create" };
  }

  const genesisPayload = genesis.payload as Record<string, unknown>;
  if (genesisPayload.prev !== null) {
    return { valid: false, error: "genesis prev must be null" };
  }

  // Verify DID derivation
  const genesisSig = fromBase64(genesis.signature);
  const computedDid = await computeDid(genesisPayload, genesisSig);
  if (computedDid !== did) {
    return { valid: false, error: "DID mismatch" };
  }

  // Verify chain links and signatures
  let currentRotationKey = multibaseDecode(
    genesisPayload.rotationKey as string,
  );

  for (let i = 0; i < operations.length; i++) {
    const op = operations[i]!;
    const opPayload = op.payload as Record<string, unknown>;
    const opSig = fromBase64(op.signature);

    // Verify signature
    const keyForVerify =
      i === 0
        ? multibaseDecode(genesisPayload.rotationKey as string)
        : currentRotationKey;

    const canonical = canonicalJson(opPayload);
    const valid = s.crypto_sign_verify_detached(
      opSig,
      s.from_string(canonical),
      keyForVerify,
    );

    if (!valid) {
      return { valid: false, error: `invalid signature at seq ${op.seq}` };
    }

    // Verify chain link (skip genesis)
    if (i > 0) {
      const prevOp = operations[i - 1]!;
      const prevSig = fromBase64(prevOp.signature);
      const expectedPrevHash = await hashOperation(
        prevOp.payload as Record<string, unknown>,
        prevSig,
      );

      if (op.prev_hash !== expectedPrevHash || opPayload.prev !== expectedPrevHash) {
        return { valid: false, error: `chain break at seq ${op.seq}` };
      }
    }

    // Track rotation key changes
    if (op.operation_type === "rotate_rotation_key") {
      currentRotationKey = multibaseDecode(opPayload.key as string);
    }
  }

  return { valid: true };
}

/**
 * Replay an operation chain to get the current state.
 */
export function replayOperations(operations: DIDOperation[]): {
  signingKey: string | null;
  rotationKey: string | null;
  handle: string | null;
  service: string | null;
} {
  let state = {
    signingKey: null as string | null,
    rotationKey: null as string | null,
    handle: null as string | null,
    service: null as string | null,
  };

  for (const op of operations) {
    const payload = op.payload as Record<string, unknown>;
    switch (op.operation_type) {
      case "create":
        state = {
          signingKey: payload.signingKey as string,
          rotationKey: payload.rotationKey as string,
          handle: payload.handle as string,
          service: payload.service as string,
        };
        break;
      case "rotate_signing_key":
        state.signingKey = payload.key as string;
        break;
      case "rotate_rotation_key":
        state.rotationKey = payload.key as string;
        break;
      case "update_handle":
        state.handle = payload.handle as string;
        break;
    }
  }

  return state;
}
