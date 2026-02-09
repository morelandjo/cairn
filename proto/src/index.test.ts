import { describe, it, expect } from "vitest";
import {
  PROTOCOL_VERSION,
  PROTOCOL_VERSION_STRING,
  PROTOCOL_NAME,
  MURMURING_NS,
  WELL_KNOWN,
  LIMITS,
  CIPHERSUITES,
  ALLOWED_MARKDOWN,
} from "./index.js";

describe("protocol constants", () => {
  it("has correct protocol name", () => {
    expect(PROTOCOL_NAME).toBe("murmuring");
  });

  it("has correct protocol version", () => {
    expect(PROTOCOL_VERSION).toEqual({ major: 0, minor: 1, patch: 0 });
    expect(PROTOCOL_VERSION_STRING).toBe("0.1.0");
  });

  it("has correct namespace URI", () => {
    expect(MURMURING_NS).toBe("https://murmuring.dev/ns#");
  });

  it("defines well-known endpoints", () => {
    expect(WELL_KNOWN.FEDERATION).toBe("/.well-known/murmuring-federation");
    expect(WELL_KNOWN.PRIVACY_MANIFEST).toBe("/.well-known/privacy-manifest");
    expect(WELL_KNOWN.WEBFINGER).toBe("/.well-known/webfinger");
  });

  it("defines reasonable limits", () => {
    expect(LIMITS.MAX_MESSAGE_BYTES).toBe(4000);
    expect(LIMITS.MAX_ATTACHMENT_BYTES).toBe(25 * 1024 * 1024);
    expect(LIMITS.MIN_BACKWARDS_COMPAT_VERSIONS).toBe(2);
  });

  it("specifies ciphersuites", () => {
    expect(CIPHERSUITES.SYMMETRIC).toBe("XChaCha20-Poly1305");
    expect(CIPHERSUITES.KEY_EXCHANGE).toBe("X3DH");
    expect(CIPHERSUITES.CURVE).toBe("X25519");
    expect(CIPHERSUITES.SIGNING).toBe("Ed25519");
    expect(CIPHERSUITES.GROUP).toBe("MLS-RFC9420");
  });

  it("includes markdown formatting options", () => {
    expect(ALLOWED_MARKDOWN).toContain("bold");
    expect(ALLOWED_MARKDOWN).toContain("italic");
    expect(ALLOWED_MARKDOWN).toContain("code");
    expect(ALLOWED_MARKDOWN).toContain("spoiler");
  });
});
