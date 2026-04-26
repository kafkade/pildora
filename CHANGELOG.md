# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Cargo workspace with three crates: `pildora-crypto` (library), `pildora-cli` (binary), `pildora-server` (binary)
- `pildora-crypto` foundation: error types, symmetric key type with zeroize-on-drop, vault module stub
- `rustfmt.toml` and `clippy.toml` with project-wide conventions (edition 2024, `unsafe` denied, pedantic warnings)
- Apple Developer enrollment guide (`docs/apple-developer-setup.md`)
- ADR-006: Tech stack consolidation — Rust for crypto, CLI, and server; Swift for iOS; TypeScript for web; Python for ETL
- Core cryptographic primitives: Argon2id key derivation, HKDF-SHA-256, AES-256-GCM encrypt/decrypt, AES-256-GCM key wrapping, X25519 key exchange, BLAKE2b hashing
- Full key hierarchy: master key derivation from password, sub-key derivation (auth key + master encryption key), vault key and item key generation, wrapping, and unwrapping
- Vault re-keying to re-wrap all item keys under a new vault key
- Recovery key generation with human-readable Crockford Base32 encoding and checksum
- Item-level encryption with per-item random keys wrapped by the vault key
- Encrypted blob format (v1) with version byte for future migration support
- Blob size padding to fixed buckets (512 B, 2 KiB, 8 KiB, 32 KiB) to prevent size-based inference
- Generic typed encryption helpers (`encrypt_json`/`decrypt_json`) for any serializable domain object
- AAD domain separation tags for all key wrapping and item encryption operations
- Cross-platform test vector file (24 vectors across 7 categories) for verifying crypto correctness on all targets
- WASM build target via `wasm-bindgen` with full encrypt/decrypt API accessible from JavaScript
- Configurable Argon2id parameters (`derive_master_key_with_params`) for resource-constrained environments
- Drug data ETL pipeline (openFDA NDC + DailyMed) with normalized JSONL output
- SQLite FTS5 search index with concept-based deduplication for drug autocomplete
- RxNorm REST API integration for drug concept normalization

### Changed

- Sync server language from Go to Rust + Axum across all documentation
- Crypto implementation decision: RustCrypto crates over libsodium bindings (updated ADR-001)
- `.gitignore` now commits `Cargo.lock` (workspace with binaries needs reproducible builds)
- Roadmap Section 8 rewritten to reflect consolidated tech stack
