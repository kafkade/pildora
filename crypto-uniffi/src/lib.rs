//! `UniFFI` bindings for [`pildora_crypto`].
//!
//! This crate is a thin FFI wrapper that exposes the `pildora-crypto` API to
//! Swift (and potentially Kotlin) via [`UniFFI`](https://mozilla.github.io/uniffi-rs/).
//! It is intentionally kept separate from the core crypto crate so that
//! `pildora-crypto` remains 100% safe Rust with no FFI concerns.
//!
//! ## Why a separate crate?
//!
//! The workspace enforces `unsafe_code = "deny"`. `UniFFI`'s generated
//! scaffolding necessarily uses `unsafe` for the `extern "C"` FFI boundary.
//! Isolating that glue here means the core crypto library's safety invariant
//! is never weakened.
//!
//! ## Generating Swift bindings
//!
//! ```bash
//! # 1. Build the library for the host (macOS)
//! cargo build -p pildora-crypto-ffi
//!
//! # 2. Generate Swift source + modulemap + header
//! cargo run -p pildora-crypto-ffi --features bindgen --bin uniffi-bindgen -- \
//!     generate --library target/debug/libpildora_crypto_ffi.dylib \
//!     --language swift \
//!     --out-dir ios/ffi-spike/generated
//! ```

// UniFFI requires owned types (Vec<u8>, String) across the FFI boundary —
// references cannot be used. Suppress the lint for all exported functions.
#![allow(clippy::needless_pass_by_value)]

uniffi::setup_scaffolding!();

mod error;
pub use error::FfiError;

use pildora_crypto::key_hierarchy::{self, MasterEncryptionKey, VaultKey};
use pildora_crypto::primitives;

// ── FFI-safe record types ────────────────────────────────────────────────────

/// Sub-keys derived from the master key, returned as a single record.
#[derive(uniffi::Record)]
pub struct SubKeys {
    /// Authentication key for SRP-6a (32 bytes).
    pub auth_key: Vec<u8>,
    /// Master Encryption Key that wraps vault keys (32 bytes).
    pub mek: Vec<u8>,
}

// ── Key derivation ───────────────────────────────────────────────────────────

/// Derive a master key from a password and salt using Argon2id.
///
/// Uses default parameters from ADR-001: 64 MiB memory, 3 iterations,
/// parallelism 1. Returns the 32-byte master key.
#[uniffi::export]
pub fn derive_master_key(password: Vec<u8>, salt: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let mk = key_hierarchy::derive_master_key(&password, &salt)?;
    Ok(mk.as_bytes().to_vec())
}

/// Derive a master key with custom Argon2id parameters.
///
/// **Warning:** different parameters produce a different key for the same
/// password. The parameters used must be stored alongside vault metadata.
#[uniffi::export]
pub fn derive_master_key_with_params(
    password: Vec<u8>,
    salt: Vec<u8>,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
) -> Result<Vec<u8>, FfiError> {
    let bytes = primitives::derive_key_argon2id_with_params(
        &password,
        &salt,
        memory_kib,
        iterations,
        parallelism,
    )?;
    Ok(bytes.to_vec())
}

/// Derive authentication key and master encryption key from a master key.
///
/// Returns a [`SubKeys`] record with `auth_key` and `mek` fields (both 32 bytes).
#[uniffi::export]
pub fn derive_sub_keys(master_key: Vec<u8>) -> Result<SubKeys, FfiError> {
    let mk = mk_from_vec(&master_key)?;
    let (auth, mek) = key_hierarchy::derive_sub_keys(&mk)?;
    Ok(SubKeys {
        auth_key: auth.as_bytes().to_vec(),
        mek: mek.as_bytes().to_vec(),
    })
}

// ── Vault key operations ─────────────────────────────────────────────────────

/// Generate a random 32-byte vault key.
#[uniffi::export]
pub fn generate_vault_key() -> Vec<u8> {
    key_hierarchy::generate_vault_key().as_bytes().to_vec()
}

/// Wrap a vault key with the master encryption key.
///
/// Returns the 60-byte wrapped vault key.
#[uniffi::export]
pub fn wrap_vault_key(vault_key: Vec<u8>, mek: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let vk = vk_from_vec(&vault_key)?;
    let mek = mek_from_vec(&mek)?;
    let wrapped = key_hierarchy::wrap_vault_key(&vk, &mek)?;
    Ok(wrapped.0)
}

/// Unwrap a vault key using the master encryption key.
///
/// Returns the 32-byte vault key.
#[uniffi::export]
pub fn unwrap_vault_key(wrapped_vk: Vec<u8>, mek: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let mek = mek_from_vec(&mek)?;
    let wrapped = key_hierarchy::WrappedVaultKey(wrapped_vk);
    let vk = key_hierarchy::unwrap_vault_key(&wrapped, &mek)?;
    Ok(vk.as_bytes().to_vec())
}

// ── Item encryption ──────────────────────────────────────────────────────────

/// Encrypt plaintext into an encrypted blob.
///
/// Returns the self-contained blob bytes (includes wrapped item key).
#[uniffi::export]
pub fn item_encrypt(plaintext: Vec<u8>, vault_key: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let vk = vk_from_vec(&vault_key)?;
    let blob = pildora_crypto::vault::item_encrypt(&plaintext, &vk)?;
    Ok(blob.to_bytes().to_vec())
}

/// Decrypt an encrypted blob back to plaintext.
#[uniffi::export]
pub fn item_decrypt(blob_bytes: Vec<u8>, vault_key: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let vk = vk_from_vec(&vault_key)?;
    let blob = pildora_crypto::vault::EncryptedBlob::from_bytes(blob_bytes)?;
    let plaintext = pildora_crypto::vault::item_decrypt(&blob, &vk)?;
    Ok(plaintext)
}

// ── JSON encryption ──────────────────────────────────────────────────────────

/// Encrypt a JSON string into an encrypted blob.
#[uniffi::export]
pub fn encrypt_json(json_string: String, vault_key: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    let vk = vk_from_vec(&vault_key)?;
    let blob = pildora_crypto::vault::item_encrypt(json_string.as_bytes(), &vk)?;
    Ok(blob.to_bytes().to_vec())
}

/// Decrypt an encrypted blob and return the JSON string.
#[uniffi::export]
pub fn decrypt_json(blob_bytes: Vec<u8>, vault_key: Vec<u8>) -> Result<String, FfiError> {
    let vk = vk_from_vec(&vault_key)?;
    let blob = pildora_crypto::vault::EncryptedBlob::from_bytes(blob_bytes)?;
    let plaintext = pildora_crypto::vault::item_decrypt(&blob, &vk)?;
    String::from_utf8(plaintext).map_err(|e| FfiError::Serialization {
        message: e.to_string(),
    })
}

// ── SQLCipher key derivation ─────────────────────────────────────────────────

/// Derive a 32-byte `SQLCipher` database key from a vault key.
///
/// Uses HKDF-SHA256 with the domain-separation label `pildora-sqlcipher-db-key`
/// so the database key is cryptographically distinct from the vault key itself
/// and from any other key derived from it. The iOS data layer hex-encodes the
/// result and hands it to `SQLCipher` as the database passphrase — one vault maps
/// to one encrypted database file, so re-keying a vault means opening a new file.
#[uniffi::export]
pub fn derive_sqlcipher_key(vault_key: Vec<u8>) -> Result<Vec<u8>, FfiError> {
    // Validate the length up front so callers get a clear FFI error.
    let _ = vk_from_vec(&vault_key)?;
    let key = primitives::hkdf_sha256(&vault_key, None, b"pildora-sqlcipher-db-key", 32)?;
    Ok(key)
}

// ── Utility ──────────────────────────────────────────────────────────────────

/// Generate a random 16-byte salt for Argon2id.
#[uniffi::export]
pub fn generate_salt() -> Vec<u8> {
    primitives::generate_salt().to_vec()
}

/// Hash data with BLAKE2b-256, returning 32 bytes.
#[uniffi::export]
pub fn blake2b_hash(data: Vec<u8>) -> Vec<u8> {
    primitives::blake2b_hash(&data).to_vec()
}

// ── Internal helpers ─────────────────────────────────────────────────────────

fn vk_from_vec(bytes: &[u8]) -> Result<VaultKey, FfiError> {
    let arr: [u8; 32] = bytes.try_into().map_err(|_| FfiError::InvalidArgument {
        message: format!("vault key must be 32 bytes, got {}", bytes.len()),
    })?;
    Ok(VaultKey::from_bytes(arr))
}

fn mek_from_vec(bytes: &[u8]) -> Result<MasterEncryptionKey, FfiError> {
    let arr: [u8; 32] = bytes.try_into().map_err(|_| FfiError::InvalidArgument {
        message: format!(
            "master encryption key must be 32 bytes, got {}",
            bytes.len()
        ),
    })?;
    Ok(MasterEncryptionKey::from_bytes(arr))
}

fn mk_from_vec(bytes: &[u8]) -> Result<key_hierarchy::MasterKey, FfiError> {
    let arr: [u8; 32] = bytes.try_into().map_err(|_| FfiError::InvalidArgument {
        message: format!("master key must be 32 bytes, got {}", bytes.len()),
    })?;
    Ok(key_hierarchy::MasterKey::from_bytes(arr))
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_derive_master_key_roundtrip() {
        let password = b"test-password".to_vec();
        let salt = generate_salt();
        let mk1 = derive_master_key(password.clone(), salt.clone()).unwrap();
        let mk2 = derive_master_key(password, salt).unwrap();
        assert_eq!(mk1, mk2);
        assert_eq!(mk1.len(), 32);
    }

    #[test]
    fn ffi_derive_sub_keys_returns_32_byte_keys() {
        let password = b"test-password".to_vec();
        let salt = generate_salt();
        let mk = derive_master_key(password, salt).unwrap();
        let sub = derive_sub_keys(mk).unwrap();
        assert_eq!(sub.auth_key.len(), 32);
        assert_eq!(sub.mek.len(), 32);
    }

    #[test]
    fn ffi_encrypt_decrypt_roundtrip() {
        let vk = generate_vault_key();
        let plaintext = b"hello from FFI!".to_vec();
        let blob = item_encrypt(plaintext.clone(), vk.clone()).unwrap();
        let decrypted = item_decrypt(blob, vk).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn ffi_json_encrypt_decrypt_roundtrip() {
        let vk = generate_vault_key();
        let json = r#"{"name":"Aspirin","dosage":"100mg"}"#.to_string();
        let blob = encrypt_json(json.clone(), vk.clone()).unwrap();
        let decrypted = decrypt_json(blob, vk).unwrap();
        assert_eq!(decrypted, json);
    }

    #[test]
    fn ffi_vault_key_wrap_unwrap_roundtrip() {
        let password = b"test-password".to_vec();
        let salt = generate_salt();
        let mk = derive_master_key(password, salt).unwrap();
        let sub = derive_sub_keys(mk).unwrap();

        let vk = generate_vault_key();
        let wrapped = wrap_vault_key(vk.clone(), sub.mek.clone()).unwrap();
        let unwrapped = unwrap_vault_key(wrapped, sub.mek).unwrap();
        assert_eq!(unwrapped, vk);
    }

    #[test]
    fn ffi_wrong_key_fails_decrypt() {
        let vk1 = generate_vault_key();
        let vk2 = generate_vault_key();
        let blob = item_encrypt(b"secret".to_vec(), vk1).unwrap();
        assert!(item_decrypt(blob, vk2).is_err());
    }

    #[test]
    fn ffi_invalid_key_length_rejected() {
        let short_key = vec![0u8; 16];
        let result = item_encrypt(b"test".to_vec(), short_key);
        assert!(result.is_err());
        match result.unwrap_err() {
            FfiError::InvalidArgument { .. } => {}
            other => panic!("expected InvalidArgument, got {other:?}"),
        }
    }

    #[test]
    fn ffi_blake2b_hash_deterministic() {
        let data = b"test data".to_vec();
        let h1 = blake2b_hash(data.clone());
        let h2 = blake2b_hash(data);
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 32);
    }

    #[test]
    fn ffi_derive_sqlcipher_key_deterministic_32_bytes() {
        let vk = generate_vault_key();
        let k1 = derive_sqlcipher_key(vk.clone()).unwrap();
        let k2 = derive_sqlcipher_key(vk.clone()).unwrap();
        assert_eq!(k1, k2);
        assert_eq!(k1.len(), 32);
        // The database key must not be the raw vault key.
        assert_ne!(k1, vk);
    }

    #[test]
    fn ffi_derive_sqlcipher_key_known_answer() {
        // Fixed vault key (32 × 0x01) → HKDF-SHA256(salt=None,
        // info="pildora-sqlcipher-db-key", L=32). Locks the derivation so any
        // change to the label or algorithm is caught across platforms.
        let vault_key = vec![1u8; 32];
        let expected =
            hex_decode("4932fed991ba6253e6a091a2cc54189cb2eb43df515ad977691d2781d70ec392");
        assert_eq!(derive_sqlcipher_key(vault_key).unwrap(), expected);
    }

    #[test]
    fn ffi_derive_sqlcipher_key_rejects_wrong_length() {
        let result = derive_sqlcipher_key(vec![0u8; 16]);
        assert!(result.is_err());
        match result.unwrap_err() {
            FfiError::InvalidArgument { .. } => {}
            other => panic!("expected InvalidArgument, got {other:?}"),
        }
    }

    fn hex_decode(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }
}
