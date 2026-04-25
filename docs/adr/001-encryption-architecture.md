# ADR-001: Encryption Architecture

**Status:** Accepted
**Date:** 2026-04-24

## Context

Pildora stores sensitive health data (medications, schedules, doses, vaccination
records). The project's foundational principle is zero-knowledge: the server
must never see plaintext user data. We need to choose cryptographic primitives,
a key hierarchy, and per-platform key storage that support this guarantee across
iOS, iPadOS, watchOS, web, and CLI.

The architecture must also support multi-vault (each vault = one encryption
boundary) and future vault sharing (granting another user access to a vault
without revealing data to the server).

## Decision

### Key Hierarchy

```text
Master Password
    → [Argon2id + salt] → Master Key (MK)
        → [HKDF-SHA-256] → Authentication Key (for SRP-6a)
        → [HKDF-SHA-256] → Master Encryption Key (MEK)
            → wraps → Vault Key (VK) per vault [AES-256-GCM keywrap]
                → wraps → Item Key (IK) per item [AES-256-GCM keywrap]
```

### Cryptographic Primitives

| Primitive | Algorithm | Purpose |
|---|---|---|
| Key derivation | Argon2id (64MB memory, 3 iterations, parallelism 1) | Master password → Master Key |
| Symmetric encryption | AES-256-GCM | Item encryption, vault metadata encryption |
| Key wrapping | AES-256-GCM keywrap | Wrapping vault keys with MEK, item keys with VK |
| Asymmetric key exchange | X25519 (Curve25519) | Vault sharing — encrypt VK to recipient's public key |
| Sub-key derivation | HKDF-SHA-256 | Deriving auth key and encryption key from MK |
| Authentication | SRP-6a (3072-bit group) | Zero-knowledge password auth with server |
| Hashing | BLAKE2b | Integrity checks, content addressing |

### Per-Platform Key Storage

| Platform | Storage | Biometric Unlock |
|---|---|---|
| iOS / iPadOS | Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly) | Face ID / Touch ID via LAContext |
| watchOS | Keychain (synced from paired iPhone) | Wrist detection |
| Web | WebCrypto API + IndexedDB (non-extractable CryptoKey) | WebAuthn / passkey |
| CLI | OS keyring (macOS Keychain, Linux secret-service, Windows Credential Manager) | None (master password or env var) |

### Recovery

Master password + printed recovery key (modeled after 1Password Emergency Kit).
If the user loses both, data is permanently unrecoverable. This is by design.
Optional iCloud Keychain backup for device unlock convenience on Apple platforms.

### Implementation

Single shared Rust library (`pildora-crypto`) compiled to:

- Native (iOS/macOS/watchOS via FFI)
- WASM (web via wasm-bindgen)
- Native binary (CLI — Rust directly)

One implementation = one audit target. Eliminates cross-platform crypto
divergence risk.

## Alternatives Considered

**Per-platform native crypto (Swift CryptoKit, WebCrypto, Go crypto):**
Rejected. Multiple implementations of the same spec increases the risk of
subtle bugs. A single Rust library ensures identical behavior everywhere and
simplifies security auditing.

**NaCl/libsodium directly:** Considered. The chosen primitives (AES-256-GCM,
X25519, Argon2id) overlap significantly with libsodium's API. **Decision
(2026-04-25): Use `RustCrypto` crates, not libsodium bindings.** RustCrypto
crates are pure Rust with no C dependencies, which ensures clean compilation
to all targets (native, WASM, iOS FFI) without C linkage issues. The
`sodiumoxide` crate is also less actively maintained. Specific crates to be
used: `aes-gcm`, `argon2`, `x25519-dalek`, `hkdf`, `sha2`, `blake2`.

**No item-level keys (vault key encrypts items directly):** Rejected. Item keys
enable future granular sharing (share a single medication record without sharing
the entire vault) and reduce the blast radius of a key compromise.

## Consequences

- The Rust crypto library is on the **critical path** — all platforms depend on
  it. Phase 0 must prioritize this.
- FFI bridging (Rust → Swift, Rust → WASM) adds build complexity and must be
  validated in technical spikes.
- Argon2id with 64MB memory may be slow on older devices — need to benchmark
  and potentially adjust parameters.
- Recovery key loss = permanent data loss. Onboarding UX must forcefully
  communicate this.
