# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- iOS Today view feature (`ios/today-view/`): chronological dose sections (morning/afternoon/evening/bedtime), dose states (upcoming/due now/overdue/taken/skipped/snoozed), one-tap confirmation with haptic feedback, swipe actions (taken/skip/snooze), PRN quick logging, and VoiceOver/Dynamic Type support.
- iOS medication list feature (`ios/medication-list/`): SwiftUI package with a searchable, category-grouped medication list, drug reference display (class, side effects, source + date attribution, informational-only disclaimer), manual inventory tracking with user-configurable low-stock thresholds and local refill reminders, a profile/settings screen, and on-device data export (decrypted JSON + Doctor Mode PDF). Self-contained against an in-memory sample store pending the data layer (#44), CRUD (#48), and design system (#43).
- `pildora-crypto-ffi` crate: UniFFI bindings exposing `pildora-crypto` to Swift via FFI (ADR-007)
- iOS FFI spike: prototype Swift app validating Rust → Swift FFI bridge with encrypt/decrypt roundtrip and benchmarks
- iOS SQLCipher spike: GRDB.swift integration with encrypted storage, 4-table data model, CRUD benchmarks, and vault-per-database architecture
- iOS notification spike: 64-notification rotation algorithm with priority-based scheduling, rolling window replenishment, and 6-scenario simulation
- iOS accessibility spike: SwiftUI prototype of medication list and dose confirmation with Dynamic Type, VoiceOver, 44pt tap targets, and programmatic audit
- ADR-007: Rust-to-Swift FFI Bridge — documents UniFFI choice, XCFramework build process, and security considerations
- `build-xcframework.sh` script for cross-compiling Rust to Apple targets and packaging as XCFramework
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
- CLI tool with clap v4: `init`, `unlock`, `lock`, `status`, `med`, `dose`, `schedule`, `export`, `recovery-key`, and shell completions (bash, zsh, fish, PowerShell)
- Encrypted local storage for the CLI using SQLite with zero-knowledge blob storage
- Vault initialization with master password, Argon2id key derivation, and recovery key generation
- Vault unlock/lock with session persistence for seamless multi-command workflows
- Recovery key display and regeneration for account recovery
- Medication CRUD commands: add (with flags for dosage, form, prescriber, pharmacy), list (table view), show (detail view with name matching), edit, and delete
- Medication schedules with flexible patterns: daily, multi-daily, every N days, specific weekdays, and PRN (as needed)
- Dose logging: log taken doses, skip with reason, view today's doses with status (taken/missed/upcoming/skipped), and dose history
- Drug autocomplete during `med add` from the local FTS5 search index with auto-populated generic name, brand name, and RxNorm ID
- Full vault data export in JSON and CSV formats via `pildora export`

### Changed

- Roadmap updated to reflect ADR decisions: libsodium → `pildora-crypto` (RustCrypto), MIT open-core → AGPL-3.0, TypeScript/Hono → Rust+Axum, cbindgen → UniFFI (17 sections reconciled)
- Sync server language from Go to Rust + Axum across all documentation
- Crypto implementation decision: RustCrypto crates over libsodium bindings (updated ADR-001)
- `.gitignore` now commits `Cargo.lock` (workspace with binaries needs reproducible builds)
- Roadmap Section 8 rewritten to reflect consolidated tech stack
