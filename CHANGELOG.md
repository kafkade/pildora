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

### Changed

- Sync server language from Go to Rust + Axum across all documentation
- Crypto implementation decision: RustCrypto crates over libsodium bindings (updated ADR-001)
- `.gitignore` now commits `Cargo.lock` (workspace with binaries needs reproducible builds)
- Roadmap Section 8 rewritten to reflect consolidated tech stack
