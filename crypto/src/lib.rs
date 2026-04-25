//! # pildora-crypto
//!
//! Zero-knowledge encryption library for [Pildora](https://github.com/kafkade/pildora).
//!
//! This crate implements the cryptographic primitives and key hierarchy that
//! all Pildora platforms depend on. It compiles to native (iOS/macOS/Watch via
//! FFI), WASM (web), and is used directly by the CLI and sync server as a
//! Cargo workspace dependency.
//!
//! ## Key Hierarchy
//!
//! ```text
//! Master Password
//!     → [Argon2id + salt] → Master Key (MK)
//!         → [HKDF-SHA-256] → Authentication Key (for SRP-6a)
//!         → [HKDF-SHA-256] → Master Encryption Key (MEK)
//!             → wraps → Vault Key (VK) per vault [AES-256-GCM keywrap]
//!                 → wraps → Item Key (IK) per item [AES-256-GCM keywrap]
//! ```
//!
//! ## Cryptographic Primitives
//!
//! | Primitive | Algorithm | Purpose |
//! |-----------|-----------|---------|
//! | Key derivation | Argon2id | Master password → Master Key |
//! | Symmetric encryption | AES-256-GCM | Item and vault metadata encryption |
//! | Key wrapping | AES-256-GCM keywrap | Wrapping vault/item keys |
//! | Asymmetric exchange | X25519 | Vault sharing key exchange |
//! | Sub-key derivation | HKDF-SHA-256 | Deriving auth and encryption keys |
//! | Authentication | SRP-6a (3072-bit) | Zero-knowledge password auth |
//! | Hashing | `BLAKE2b` | Integrity checks |
//!
//! ## Design Principles
//!
//! - **Single implementation**: One Rust crate, one audit target, zero
//!   cross-platform divergence.
//! - **Sensitive memory**: All key material implements [`zeroize::Zeroize`] and
//!   is cleared on drop.
//! - **No unsafe code**: The crate forbids `unsafe` — all crypto operations
//!   use safe Rust via the `RustCrypto` ecosystem.

pub mod error;
pub mod key_hierarchy;
pub mod keys;
pub mod primitives;
pub mod vault;

/// Encrypted blob version. Embedded as the first byte of every encrypted blob
/// to enable client-side schema migration on decryption.
pub const BLOB_VERSION: u8 = 1;
