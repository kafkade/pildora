# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Pildora — especially in the encryption layer, key management, or sync protocol — **please do not open a public issue.**

Instead, please report it responsibly:

1. **Email**: [TODO: set up security contact email]
2. **Include**: A description of the vulnerability, steps to reproduce, and potential impact
3. **Response time**: We aim to acknowledge reports within 48 hours and provide a fix timeline within 7 days

## Scope

The following are in scope for security reports:

- Encryption implementation bugs in `pildora-crypto`
- Key derivation, storage, or wrapping vulnerabilities
- SRP authentication bypass or weaknesses
- Vault sync protocol vulnerabilities
- Data leakage (plaintext health data leaving the device unintentionally)
- Metadata exposure beyond what is documented in the threat model

## Out of Scope

- Vulnerabilities in third-party dependencies (report to the upstream project)
- Social engineering attacks
- Physical device access attacks (if someone has your unlocked phone, all bets are off)
- Denial of service

## Security Design Philosophy

Pildora follows [Kerckhoffs's principle](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle): the security of the system does not depend on the secrecy of its design. Our cryptographic architecture, key hierarchy, and sync protocol are fully documented in this public repository. The only secret is your master password — which never leaves your device.

This is why we publish our encryption design openly and welcome independent review. If the system's security required hiding how it works, it wouldn't be secure enough.

## Encryption Audit

The `pildora-crypto` library is open-source and available for independent security review. We welcome and encourage third-party audits.

A formal, funded security audit is planned for Phase 8 of the project roadmap.
