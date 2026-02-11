# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Murmuring, please report it responsibly.

**Do NOT open a public issue.**

### How to Report

Email: **security@murmuring.dev**

Include:
- A description of the vulnerability
- Steps to reproduce
- Affected versions (if known)
- Any potential impact assessment

### Response Timeline

| Stage | Timeline |
|-------|----------|
| Acknowledgment | Within 48 hours |
| Triage & severity assessment | Within 1 week |
| Fix development | Depends on severity |
| Patch release | Critical: 72 hours, High: 1 week, Medium: next release |
| Public disclosure | After fix is released + 30-day grace period |

### Scope

The following are in scope:
- Server API (Phoenix endpoints)
- Authentication & authorization
- E2E encryption (MLS, Double Ratchet, key management)
- Federation protocol (HTTP signatures, ActivityPub)
- WebSocket handling
- File upload & processing
- Voice/video signaling
- Desktop & mobile clients

### Safe Harbor

We consider security research conducted in good faith to be authorized. We will not pursue legal action against researchers who:
- Make a good faith effort to avoid privacy violations, data destruction, or service disruption
- Only interact with accounts they own or with explicit permission
- Report vulnerabilities through the process described above
- Allow reasonable time for remediation before disclosure

### Recognition

We maintain a hall of fame for security researchers who responsibly disclose vulnerabilities. If you'd like to be credited, please let us know in your report.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Security Architecture

For details on Murmuring's security architecture, trust model, and threat mitigations, see [docs/security/threat-model.md](docs/security/threat-model.md).
