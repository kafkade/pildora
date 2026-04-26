# pildora-crypto

Shared zero-knowledge encryption library for
[Pildora](https://github.com/kafkade/pildora).

## Overview

This Rust crate implements the cryptographic primitives and key hierarchy used
across all Pildora platforms. One implementation = one audit target = zero
cross-platform divergence risk.

### Primitives

| Primitive | Algorithm | Purpose |
|---|---|---|
| Key derivation | Argon2id (64 MiB, 3 iterations — configurable) | Master password → Master Key |
| Symmetric encryption | AES-256-GCM | Item and vault metadata encryption |
| Key wrapping | AES-256-GCM keywrap | Wrapping vault/item keys |
| Asymmetric exchange | X25519 | Vault sharing key exchange |
| Sub-key derivation | HKDF-SHA-256 | Auth key + encryption key from MK |
| Authentication | SRP-6a (3072-bit) | Zero-knowledge password auth |
| Hashing | BLAKE2b | Integrity checks |

### Key Hierarchy

```text
Master Password
    → [Argon2id + salt] → Master Key (MK)
        → [HKDF] → Authentication Key (for SRP-6a)
        → [HKDF] → Master Encryption Key (MEK)
            → wraps → Vault Key (VK) per vault
                → wraps → Item Key (IK) per item
```

## Implementation

Uses **RustCrypto** crates (pure Rust, no C dependencies). This ensures clean
compilation to all targets without C linkage issues.

See [ADR-001](../docs/adr/001-encryption-architecture.md) for architecture
decisions.

## Compilation Targets

| Target | Usage |
|---|---|
| Native (aarch64-apple-darwin, x86_64) | iOS/macOS/Watch via FFI, CLI, server |
| WASM (wasm32-unknown-unknown) | Web app via wasm-bindgen |

## Building

### Native

```sh
# Build
cargo build -p pildora-crypto

# Test
cargo test -p pildora-crypto

# Lint
cargo clippy -p pildora-crypto -- -D warnings

# Format check
cargo fmt -p pildora-crypto -- --check
```

### WASM

```sh
# Build for web
wasm-pack build crypto --target web --features wasm

# Build for Node.js
wasm-pack build crypto --target nodejs --features wasm

# Run Node.js test harness
node crypto/tests/wasm_node_test.cjs
```

> Run from the repository root, or omit `crypto` when running from within the
> crate directory.

The WASM build uses the same cryptographic implementation as native. Argon2id
parameters default to 64 MiB memory — use `derive_master_key_with_params` for
constrained environments. **Different parameters produce different keys;** store
them with vault metadata.

## Design Principles

- **No unsafe code** — the crate forbids `unsafe`.
- **Zeroize on drop** — all key material implements `Zeroize` and is cleared
  when values go out of scope.
- **Cross-platform test vectors** — a JSON test vector file validates that
  native, WASM, and FFI builds produce identical output.

## Status

✅ The crypto library is **complete and stable** — all cryptographic primitives,
key hierarchy, item-level encryption, cross-platform test vectors, and WASM
build target are implemented and tested. Argon2id parameters are configurable
via `derive_key_argon2id_with_params` for resource-constrained environments
(e.g., WASM in browsers). Different parameters produce different keys, so
parameters must be stored with vault metadata.
