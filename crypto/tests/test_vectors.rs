//! Integration tests that validate every test vector in `test-vectors/vectors.json`.
//!
//! These tests ensure that the Rust implementation produces the exact same
//! outputs that Swift FFI and WASM bindings must match, guaranteeing
//! cross-platform correctness.

use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use serde::Deserialize;

use pildora_crypto::key_hierarchy;
use pildora_crypto::primitives;
use pildora_crypto::vault;

// ── Vector file (embedded at compile time) ──────────────────────────────────

const VECTORS_JSON: &str = include_str!("../test-vectors/vectors.json");

// ── Deserialization types ───────────────────────────────────────────────────

#[derive(Deserialize)]
struct VectorFile {
    version: String,
    vectors: Vectors,
}

#[derive(Deserialize)]
struct Vectors {
    argon2id: Vec<Argon2idVector>,
    hkdf_sha256: Vec<HkdfVector>,
    aes256_gcm: Vec<AesGcmVector>,
    keywrap: Vec<KeywrapVector>,
    blake2b: Vec<Blake2bVector>,
    key_hierarchy: Vec<KeyHierarchyVector>,
    item_encryption: Vec<ItemEncryptionVector>,
}

#[derive(Deserialize)]
struct Argon2idVector {
    description: String,
    password_hex: String,
    salt_hex: String,
    expected_key_hex: String,
}

#[derive(Deserialize)]
struct HkdfVector {
    description: String,
    ikm_hex: String,
    salt_hex: Option<String>,
    info: String,
    output_len: usize,
    expected_output_hex: String,
}

#[derive(Deserialize)]
struct AesGcmVector {
    description: String,
    key_hex: String,
    nonce_hex: String,
    plaintext_hex: String,
    aad_hex: String,
    expected_ciphertext_hex: String,
}

#[derive(Deserialize)]
struct KeywrapVector {
    description: String,
    wrapping_key_hex: String,
    key_to_wrap_hex: String,
    aad: String,
    nonce_hex: String,
    expected_wrapped_hex: String,
}

#[derive(Deserialize)]
struct Blake2bVector {
    description: String,
    #[serde(default)]
    key_hex: Option<String>,
    input_hex: String,
    expected_hash_hex: String,
}

#[derive(Deserialize)]
struct KeyHierarchyVector {
    description: String,
    password_hex: String,
    salt_hex: String,
    expected_mk_hex: String,
    expected_auth_key_hex: String,
    expected_mek_hex: String,
}

#[derive(Deserialize)]
struct ItemEncryptionVector {
    description: String,
    vault_key_hex: String,
    plaintext_hex: String,
    blob_hex: String,
    blob_version: u8,
}

// ── Helper ──────────────────────────────────────────────────────────────────

fn load_vectors() -> VectorFile {
    serde_json::from_str(VECTORS_JSON).expect("failed to parse vectors.json")
}

fn to_32(bytes: &[u8]) -> [u8; 32] {
    let mut arr = [0u8; 32];
    arr.copy_from_slice(bytes);
    arr
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[test]
fn vector_file_version() {
    let vf = load_vectors();
    assert_eq!(vf.version, "1.0");
}

#[test]
fn argon2id_vectors() {
    let vf = load_vectors();
    assert!(!vf.vectors.argon2id.is_empty(), "no argon2id vectors found");

    for v in &vf.vectors.argon2id {
        let password = hex::decode(&v.password_hex).unwrap();
        let salt = hex::decode(&v.salt_hex).unwrap();
        let expected = hex::decode(&v.expected_key_hex).unwrap();

        let result = primitives::derive_key_argon2id(&password, &salt)
            .unwrap_or_else(|e| panic!("{}: Argon2id failed: {e}", v.description));

        assert_eq!(
            result.as_slice(),
            expected.as_slice(),
            "Argon2id mismatch: {}",
            v.description
        );
    }
}

#[test]
fn hkdf_vectors() {
    let vf = load_vectors();
    assert!(!vf.vectors.hkdf_sha256.is_empty(), "no HKDF vectors found");

    for v in &vf.vectors.hkdf_sha256 {
        let ikm = hex::decode(&v.ikm_hex).unwrap();
        let salt = v.salt_hex.as_ref().map(|s| hex::decode(s).unwrap());
        let expected = hex::decode(&v.expected_output_hex).unwrap();

        let result =
            primitives::hkdf_sha256(&ikm, salt.as_deref(), v.info.as_bytes(), v.output_len)
                .unwrap_or_else(|e| panic!("{}: HKDF failed: {e}", v.description));

        assert_eq!(result, expected, "HKDF mismatch: {}", v.description);
    }
}

#[test]
fn aes256_gcm_vectors() {
    let vf = load_vectors();
    assert!(
        !vf.vectors.aes256_gcm.is_empty(),
        "no AES-GCM vectors found"
    );

    for v in &vf.vectors.aes256_gcm {
        let key_bytes = hex::decode(&v.key_hex).unwrap();
        let nonce_bytes = hex::decode(&v.nonce_hex).unwrap();
        let plaintext = hex::decode(&v.plaintext_hex).unwrap();
        let aad = hex::decode(&v.aad_hex).unwrap();
        let expected = hex::decode(&v.expected_ciphertext_hex).unwrap();

        // Encrypt with explicit nonce using aes-gcm directly
        let cipher = Aes256Gcm::new_from_slice(&key_bytes).unwrap();
        let nonce = Nonce::from_slice(&nonce_bytes);
        let payload = aes_gcm::aead::Payload {
            msg: plaintext.as_slice(),
            aad: &aad,
        };
        let ct_and_tag = cipher.encrypt(nonce, payload).unwrap();

        // Reconstruct nonce || ct || tag
        let mut full = Vec::with_capacity(12 + ct_and_tag.len());
        full.extend_from_slice(&nonce_bytes);
        full.extend_from_slice(&ct_and_tag);

        assert_eq!(
            full, expected,
            "AES-GCM encrypt mismatch: {}",
            v.description
        );

        // Verify decryption via the library
        let decrypted = primitives::aes256_gcm_decrypt(&to_32(&key_bytes), &expected, &aad)
            .unwrap_or_else(|e| panic!("{}: AES-GCM decrypt failed: {e}", v.description));

        assert_eq!(
            decrypted, plaintext,
            "AES-GCM decrypt mismatch: {}",
            v.description
        );
    }
}

#[test]
fn keywrap_vectors() {
    let vf = load_vectors();
    assert!(!vf.vectors.keywrap.is_empty(), "no keywrap vectors found");

    for v in &vf.vectors.keywrap {
        let wrapping_key = hex::decode(&v.wrapping_key_hex).unwrap();
        let key_to_wrap = hex::decode(&v.key_to_wrap_hex).unwrap();
        let nonce_bytes = hex::decode(&v.nonce_hex).unwrap();
        let expected = hex::decode(&v.expected_wrapped_hex).unwrap();
        let aad = v.aad.as_bytes();

        // Encrypt with explicit nonce using aes-gcm directly
        let cipher = Aes256Gcm::new_from_slice(&wrapping_key).unwrap();
        let nonce = Nonce::from_slice(&nonce_bytes);
        let payload = aes_gcm::aead::Payload {
            msg: key_to_wrap.as_slice(),
            aad,
        };
        let ct_and_tag = cipher.encrypt(nonce, payload).unwrap();

        let mut full = Vec::with_capacity(12 + ct_and_tag.len());
        full.extend_from_slice(&nonce_bytes);
        full.extend_from_slice(&ct_and_tag);

        assert_eq!(
            full, expected,
            "Keywrap encrypt mismatch: {}",
            v.description
        );

        // Verify unwrap via the library
        let unwrapped = primitives::aes256_gcm_key_unwrap(&to_32(&wrapping_key), &expected, aad)
            .unwrap_or_else(|e| panic!("{}: unwrap failed: {e}", v.description));

        assert_eq!(
            unwrapped.as_slice(),
            key_to_wrap.as_slice(),
            "Keywrap unwrap mismatch: {}",
            v.description
        );
    }
}

#[test]
fn blake2b_vectors() {
    let vf = load_vectors();
    assert!(!vf.vectors.blake2b.is_empty(), "no BLAKE2b vectors found");

    for v in &vf.vectors.blake2b {
        let input = hex::decode(&v.input_hex).unwrap();
        let expected = hex::decode(&v.expected_hash_hex).unwrap();

        match &v.key_hex {
            Some(key_hex) => {
                // Keyed MAC
                let key = hex::decode(key_hex).unwrap();
                let result = primitives::blake2b_mac(&key, &input)
                    .unwrap_or_else(|e| panic!("{}: BLAKE2b MAC failed: {e}", v.description));
                assert_eq!(
                    result.as_slice(),
                    expected.as_slice(),
                    "BLAKE2b MAC mismatch: {}",
                    v.description
                );
            }
            None => {
                // Unkeyed hash
                let result = primitives::blake2b_hash(&input);
                assert_eq!(
                    result.as_slice(),
                    expected.as_slice(),
                    "BLAKE2b hash mismatch: {}",
                    v.description
                );
            }
        }
    }
}

#[test]
fn key_hierarchy_vectors() {
    let vf = load_vectors();
    assert!(
        !vf.vectors.key_hierarchy.is_empty(),
        "no key hierarchy vectors found"
    );

    for v in &vf.vectors.key_hierarchy {
        let password = hex::decode(&v.password_hex).unwrap();
        let salt = hex::decode(&v.salt_hex).unwrap();
        let expected_mk = hex::decode(&v.expected_mk_hex).unwrap();
        let expected_auth = hex::decode(&v.expected_auth_key_hex).unwrap();
        let expected_mek = hex::decode(&v.expected_mek_hex).unwrap();

        let mk = key_hierarchy::derive_master_key(&password, &salt)
            .unwrap_or_else(|e| panic!("{}: derive_master_key failed: {e}", v.description));

        assert_eq!(
            mk.as_bytes().as_slice(),
            expected_mk.as_slice(),
            "MK mismatch: {}",
            v.description
        );

        let (auth, mek) = key_hierarchy::derive_sub_keys(&mk)
            .unwrap_or_else(|e| panic!("{}: derive_sub_keys failed: {e}", v.description));

        assert_eq!(
            auth.as_bytes().as_slice(),
            expected_auth.as_slice(),
            "Auth key mismatch: {}",
            v.description
        );

        assert_eq!(
            mek.as_bytes().as_slice(),
            expected_mek.as_slice(),
            "MEK mismatch: {}",
            v.description
        );
    }
}

#[test]
fn item_encryption_vectors() {
    let vf = load_vectors();
    assert!(
        !vf.vectors.item_encryption.is_empty(),
        "no item encryption vectors found"
    );

    for v in &vf.vectors.item_encryption {
        let vault_key_bytes = hex::decode(&v.vault_key_hex).unwrap();
        let expected_plaintext = hex::decode(&v.plaintext_hex).unwrap();
        let blob_bytes = hex::decode(&v.blob_hex).unwrap();

        assert_eq!(
            v.blob_version, 1,
            "unsupported blob version: {}",
            v.description
        );

        // Parse the blob
        let blob = vault::EncryptedBlob::from_bytes(blob_bytes)
            .unwrap_or_else(|e| panic!("{}: EncryptedBlob::from_bytes failed: {e}", v.description));

        assert_eq!(
            blob.version(),
            1,
            "blob version mismatch: {}",
            v.description
        );

        // Decrypt with the vault key
        let vk = key_hierarchy::VaultKey::from_bytes(to_32(&vault_key_bytes));
        let decrypted = vault::item_decrypt(&blob, &vk)
            .unwrap_or_else(|e| panic!("{}: item_decrypt failed: {e}", v.description));

        assert_eq!(
            decrypted, expected_plaintext,
            "Item decryption mismatch: {}",
            v.description
        );
    }
}
