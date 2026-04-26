//! WASM bindings for `pildora-crypto`.
//!
//! Exposes key derivation, encryption, and decryption functions to JavaScript
//! via `wasm-bindgen`. Gated behind the `wasm` feature.
//!
//! ## Usage from JavaScript
//!
//! ```js
//! import init, {
//!   derive_master_key, derive_sub_keys,
//!   item_encrypt, item_decrypt,
//!   generate_salt, generate_vault_key,
//! } from './pildora_crypto.js';
//!
//! await init();
//! const salt = generate_salt();
//! const masterKey = derive_master_key(password, salt);
//! ```
//!
//! ## Argon2id Memory
//!
//! The default `derive_master_key` uses 64 MiB memory, which may be slow in
//! browser environments. Use `derive_master_key_with_params` for custom
//! parameters. **Different parameters produce different keys** — store them
//! alongside vault metadata.

use wasm_bindgen::prelude::*;

use crate::key_hierarchy::{self, MasterEncryptionKey, VaultKey};
use crate::primitives;

// ── Key derivation ───────────────────────────────────────────────────────────

/// Derive a master key from a password and salt using Argon2id (64 MiB).
///
/// Returns the 32-byte master key.
#[wasm_bindgen]
pub fn derive_master_key(password: &[u8], salt: &[u8]) -> Result<Vec<u8>, JsError> {
    let mk = key_hierarchy::derive_master_key(password, salt)
        .map_err(|e| JsError::new(&e.to_string()))?;
    Ok(mk.as_bytes().to_vec())
}

/// Derive a master key with custom Argon2id parameters.
///
/// Use this when 64 MiB is too expensive (e.g. browser environments).
/// **Warning:** different parameters produce a different key for the same
/// password. Store the parameters alongside vault metadata.
#[wasm_bindgen]
pub fn derive_master_key_with_params(
    password: &[u8],
    salt: &[u8],
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
) -> Result<Vec<u8>, JsError> {
    let bytes = primitives::derive_key_argon2id_with_params(
        password,
        salt,
        memory_kib,
        iterations,
        parallelism,
    )
    .map_err(|e| JsError::new(&e.to_string()))?;
    Ok(bytes.to_vec())
}

/// Derive authentication key and master encryption key from a master key.
///
/// Returns a JS object with `auth_key` and `mek` fields (both `Uint8Array`).
#[wasm_bindgen]
pub fn derive_sub_keys(master_key: &[u8]) -> Result<JsValue, JsError> {
    if master_key.len() != 32 {
        return Err(JsError::new("master key must be 32 bytes"));
    }
    let mut mk_bytes = [0u8; 32];
    mk_bytes.copy_from_slice(master_key);
    let mk = key_hierarchy::MasterKey::from_bytes(mk_bytes);

    let (auth, mek) =
        key_hierarchy::derive_sub_keys(&mk).map_err(|e| JsError::new(&e.to_string()))?;

    let obj = js_sys::Object::new();
    let auth_arr = js_sys::Uint8Array::from(auth.as_bytes().as_slice());
    let mek_arr = js_sys::Uint8Array::from(mek.as_bytes().as_slice());
    js_sys::Reflect::set(&obj, &"auth_key".into(), &auth_arr)
        .map_err(|e| JsError::new(&format!("{e:?}")))?;
    js_sys::Reflect::set(&obj, &"mek".into(), &mek_arr)
        .map_err(|e| JsError::new(&format!("{e:?}")))?;
    Ok(obj.into())
}

// ── Vault key operations ─────────────────────────────────────────────────────

/// Generate a random 32-byte vault key.
#[wasm_bindgen]
pub fn generate_vault_key() -> Vec<u8> {
    key_hierarchy::generate_vault_key().as_bytes().to_vec()
}

/// Wrap a vault key with the master encryption key.
///
/// Returns the 60-byte wrapped vault key.
#[wasm_bindgen]
pub fn wrap_vault_key(vault_key: &[u8], mek: &[u8]) -> Result<Vec<u8>, JsError> {
    let vk = vk_from_slice(vault_key)?;
    let mek = mek_from_slice(mek)?;
    let wrapped =
        key_hierarchy::wrap_vault_key(&vk, &mek).map_err(|e| JsError::new(&e.to_string()))?;
    Ok(wrapped.0)
}

/// Unwrap a vault key using the master encryption key.
///
/// Returns the 32-byte vault key.
#[wasm_bindgen]
pub fn unwrap_vault_key(wrapped_vk: &[u8], mek: &[u8]) -> Result<Vec<u8>, JsError> {
    let mek = mek_from_slice(mek)?;
    let wrapped = key_hierarchy::WrappedVaultKey(wrapped_vk.to_vec());
    let vk = key_hierarchy::unwrap_vault_key(&wrapped, &mek)
        .map_err(|e| JsError::new(&e.to_string()))?;
    Ok(vk.as_bytes().to_vec())
}

// ── Item encryption ──────────────────────────────────────────────────────────

/// Encrypt plaintext into an encrypted blob.
///
/// Returns the blob bytes (self-contained: includes wrapped item key).
#[wasm_bindgen]
pub fn item_encrypt(plaintext: &[u8], vault_key: &[u8]) -> Result<Vec<u8>, JsError> {
    let vk = vk_from_slice(vault_key)?;
    let blob =
        crate::vault::item_encrypt(plaintext, &vk).map_err(|e| JsError::new(&e.to_string()))?;
    Ok(blob.to_bytes().to_vec())
}

/// Decrypt an encrypted blob back to plaintext.
#[wasm_bindgen]
pub fn item_decrypt(blob_bytes: &[u8], vault_key: &[u8]) -> Result<Vec<u8>, JsError> {
    let vk = vk_from_slice(vault_key)?;
    let blob = crate::vault::EncryptedBlob::from_bytes(blob_bytes.to_vec())
        .map_err(|e| JsError::new(&e.to_string()))?;
    crate::vault::item_decrypt(&blob, &vk).map_err(|e| JsError::new(&e.to_string()))
}

// ── JSON encryption ──────────────────────────────────────────────────────────

/// Encrypt a JSON string into an encrypted blob.
#[wasm_bindgen]
pub fn encrypt_json(json_string: &str, vault_key: &[u8]) -> Result<Vec<u8>, JsError> {
    let vk = vk_from_slice(vault_key)?;
    let blob = crate::vault::item_encrypt(json_string.as_bytes(), &vk)
        .map_err(|e| JsError::new(&e.to_string()))?;
    Ok(blob.to_bytes().to_vec())
}

/// Decrypt an encrypted blob and return the JSON string.
#[wasm_bindgen]
pub fn decrypt_json(blob_bytes: &[u8], vault_key: &[u8]) -> Result<String, JsError> {
    let vk = vk_from_slice(vault_key)?;
    let blob = crate::vault::EncryptedBlob::from_bytes(blob_bytes.to_vec())
        .map_err(|e| JsError::new(&e.to_string()))?;
    let plaintext =
        crate::vault::item_decrypt(&blob, &vk).map_err(|e| JsError::new(&e.to_string()))?;
    String::from_utf8(plaintext).map_err(|e| JsError::new(&e.to_string()))
}

// ── Utility ──────────────────────────────────────────────────────────────────

/// Generate a random 16-byte salt for Argon2id.
#[wasm_bindgen]
pub fn generate_salt() -> Vec<u8> {
    primitives::generate_salt().to_vec()
}

/// Hash data with BLAKE2b-256.
#[wasm_bindgen]
pub fn blake2b_hash(data: &[u8]) -> Vec<u8> {
    primitives::blake2b_hash(data).to_vec()
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn vk_from_slice(bytes: &[u8]) -> Result<VaultKey, JsError> {
    if bytes.len() != 32 {
        return Err(JsError::new("vault key must be 32 bytes"));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(bytes);
    Ok(VaultKey::from_bytes(arr))
}

fn mek_from_slice(bytes: &[u8]) -> Result<MasterEncryptionKey, JsError> {
    if bytes.len() != 32 {
        return Err(JsError::new("master encryption key must be 32 bytes"));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(bytes);
    Ok(MasterEncryptionKey::from_bytes(arr))
}
