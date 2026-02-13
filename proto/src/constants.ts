/**
 * Cairn Protocol Constants
 */

import type { ProtocolVersion } from "./types.js";

/** Current protocol version */
export const PROTOCOL_VERSION: ProtocolVersion = {
  major: 0,
  minor: 1,
  patch: 0,
};

/** Protocol version as a string */
export const PROTOCOL_VERSION_STRING = `${PROTOCOL_VERSION.major}.${PROTOCOL_VERSION.minor}.${PROTOCOL_VERSION.patch}`;

/** Protocol name identifier */
export const PROTOCOL_NAME = "cairn";

/** Namespace URI for ActivityPub extensions */
export const CAIRN_NS = "https://cairn.chat/ns#";

/** Well-known endpoint paths */
export const WELL_KNOWN = {
  FEDERATION: "/.well-known/cairn-federation",
  PRIVACY_MANIFEST: "/.well-known/privacy-manifest",
  WEBFINGER: "/.well-known/webfinger",
} as const;

/** Allowed Markdown subset for message formatting */
export const ALLOWED_MARKDOWN = [
  "bold",
  "italic",
  "strikethrough",
  "code",
  "codeBlock",
  "blockquote",
  "link",
  "unorderedList",
  "orderedList",
  "heading",
  "spoiler",
] as const;

/** Protocol limits */
export const LIMITS = {
  /** Maximum message content length in UTF-8 bytes */
  MAX_MESSAGE_BYTES: 4000,
  /** Maximum number of embeds per message */
  MAX_EMBEDS: 5,
  /** Maximum file attachment size in bytes (25 MB) */
  MAX_ATTACHMENT_BYTES: 25 * 1024 * 1024,
  /** Maximum channel name length */
  MAX_CHANNEL_NAME: 100,
  /** Maximum server name length */
  MAX_SERVER_NAME: 100,
  /** Maximum number of reactions per message */
  MAX_REACTIONS_PER_MESSAGE: 20,
  /** Maximum number of one-time prekeys to upload */
  MAX_ONETIME_PREKEYS: 100,
  /** Minimum backwards-compatible protocol versions */
  MIN_BACKWARDS_COMPAT_VERSIONS: 2,
} as const;

/** Supported ciphersuites for E2EE */
export const CIPHERSUITES = {
  /** Symmetric encryption algorithm */
  SYMMETRIC: "XChaCha20-Poly1305",
  /** Key exchange for DMs */
  KEY_EXCHANGE: "X3DH",
  /** Key agreement curve */
  CURVE: "X25519",
  /** Signing algorithm */
  SIGNING: "Ed25519",
  /** Group messaging protocol */
  GROUP: "MLS-RFC9420",
  /** Hash function */
  HASH: "BLAKE2b-256",
} as const;
