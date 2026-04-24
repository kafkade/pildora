# pildora-crypto

Shared zero-knowledge encryption library for Pildora.

## Overview

This Rust library implements the core cryptographic operations used across all Pildora platforms:

- **Key derivation**: Argon2id from master password
- **Symmetric encryption**: AES-256-GCM (vault item encryption)
- **Asymmetric key exchange**: X25519 (vault sharing)
- **Key wrapping**: HKDF-SHA256 (Master Key → Vault Keys → Item Keys)
- **Zero-knowledge auth**: SRP-6a client

## Compilation Targets

| Target | Usage |
|---|---|
| Native (aarch64-apple-darwin, x86_64) | iOS/macOS/Watch via FFI, CLI |
| WASM (wasm32-unknown-unknown) | Web app via wasm-bindgen |

## Status

🚧 Not yet implemented. Architecture decisions are documented in the [roadmap](../docs/roadmap.md) (Section 14.4 — ADRs).
