//! Generate deterministic test vectors for cross-platform validation.
//!
//! Usage: `cargo run -p pildora-crypto --bin generate_vectors > crypto/test-vectors/vectors.json`

use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use serde_json::{Value, json};

use pildora_crypto::key_hierarchy;
use pildora_crypto::primitives;
use pildora_crypto::vault;

fn main() {
    let mut vectors = serde_json::Map::new();

    vectors.insert("argon2id".into(), generate_argon2id());
    vectors.insert("hkdf_sha256".into(), generate_hkdf());
    vectors.insert("aes256_gcm".into(), generate_aes_gcm());
    vectors.insert("keywrap".into(), generate_keywrap());
    vectors.insert("blake2b".into(), generate_blake2b());
    vectors.insert("key_hierarchy".into(), generate_key_hierarchy());
    vectors.insert("item_encryption".into(), generate_item_encryption());

    let root = json!({
        "version": "1.0",
        "generated_by": "pildora-crypto generate_vectors",
        "vectors": vectors,
    });

    println!(
        "{}",
        serde_json::to_string_pretty(&root).expect("JSON serialization failed")
    );
}

// ── Argon2id ────────────────────────────────────────────────────────────────

fn generate_argon2id() -> Value {
    let cases: Vec<(&str, &[u8], &[u8])> = vec![
        (
            "Basic password derivation",
            b"password",
            b"somesalt12345678",
        ),
        ("Empty password", b"", b"saltsaltsaltsalt"),
        (
            "UTF-8 password with special characters",
            "pässwörd!@#$%".as_bytes(),
            b"randomsalt123456",
        ),
        (
            "Long password (64 bytes)",
            b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            b"differentsalt___",
        ),
    ];

    cases
        .into_iter()
        .map(|(desc, password, salt)| {
            let key = primitives::derive_key_argon2id(password, salt)
                .expect("Argon2id derivation failed");
            json!({
                "description": desc,
                "password_hex": hex::encode(password),
                "salt_hex": hex::encode(salt),
                "expected_key_hex": hex::encode(key),
            })
        })
        .collect()
}

// ── HKDF-SHA-256 ────────────────────────────────────────────────────────────

fn generate_hkdf() -> Value {
    let mk_bytes = [0x42u8; 32];

    let mut result = Vec::new();

    // Auth key derivation
    let auth =
        primitives::hkdf_sha256(&mk_bytes, None, b"pildora:v1:auth-key", 32).expect("HKDF failed");
    result.push(json!({
        "description": "Auth key derivation (no salt)",
        "ikm_hex": hex::encode(mk_bytes),
        "salt_hex": null,
        "info": "pildora:v1:auth-key",
        "output_len": 32,
        "expected_output_hex": hex::encode(&auth),
    }));

    // MEK derivation
    let mek = primitives::hkdf_sha256(&mk_bytes, None, b"pildora:v1:master-encryption-key", 32)
        .expect("HKDF failed");
    result.push(json!({
        "description": "Master encryption key derivation (no salt)",
        "ikm_hex": hex::encode(mk_bytes),
        "salt_hex": null,
        "info": "pildora:v1:master-encryption-key",
        "output_len": 32,
        "expected_output_hex": hex::encode(&mek),
    }));

    // With explicit salt
    let salt = [0x01u8; 16];
    let out =
        primitives::hkdf_sha256(&mk_bytes, Some(&salt), b"custom-info", 64).expect("HKDF failed");
    result.push(json!({
        "description": "HKDF with explicit salt and 64-byte output",
        "ikm_hex": hex::encode(mk_bytes),
        "salt_hex": hex::encode(salt),
        "info": "custom-info",
        "output_len": 64,
        "expected_output_hex": hex::encode(&out),
    }));

    Value::Array(result)
}

// ── AES-256-GCM (explicit nonce via aes-gcm crate directly) ─────────────

fn aes_gcm_encrypt_explicit(
    key: &[u8; 32],
    nonce: &[u8; 12],
    plaintext: &[u8],
    aad: &[u8],
) -> Vec<u8> {
    let cipher = Aes256Gcm::new_from_slice(key).expect("invalid key");
    let nonce_obj = Nonce::from_slice(nonce);
    let payload = aes_gcm::aead::Payload {
        msg: plaintext,
        aad,
    };
    let ct_and_tag = cipher
        .encrypt(nonce_obj, payload)
        .expect("encryption failed");
    // Return nonce || ciphertext || tag
    let mut out = Vec::with_capacity(12 + ct_and_tag.len());
    out.extend_from_slice(nonce);
    out.extend_from_slice(&ct_and_tag);
    out
}

fn generate_aes_gcm() -> Value {
    let key = [0xAA_u8; 32];
    let nonce = [0x00_u8; 12];

    let mut result = Vec::new();

    // Empty plaintext, no AAD
    let ct = aes_gcm_encrypt_explicit(&key, &nonce, b"", b"");
    result.push(json!({
        "description": "Encrypt empty plaintext, no AAD",
        "key_hex": hex::encode(key),
        "nonce_hex": hex::encode(nonce),
        "plaintext_hex": "",
        "aad_hex": "",
        "expected_ciphertext_hex": hex::encode(&ct),
    }));

    // Short plaintext with AAD
    let plaintext = b"hello world";
    let aad = b"pildora:v1:item-blob";
    let nonce2 = [0x01_u8; 12];
    let ct2 = aes_gcm_encrypt_explicit(&key, &nonce2, plaintext, aad);
    result.push(json!({
        "description": "Short plaintext with AAD",
        "key_hex": hex::encode(key),
        "nonce_hex": hex::encode(nonce2),
        "plaintext_hex": hex::encode(plaintext),
        "aad_hex": hex::encode(aad),
        "expected_ciphertext_hex": hex::encode(&ct2),
    }));

    // 256 bytes plaintext, no AAD
    let plaintext3 = vec![0xBB_u8; 256];
    let nonce3: [u8; 12] = [
        0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
    ];
    let ct3 = aes_gcm_encrypt_explicit(&key, &nonce3, &plaintext3, b"");
    result.push(json!({
        "description": "256-byte plaintext, no AAD",
        "key_hex": hex::encode(key),
        "nonce_hex": hex::encode(nonce3),
        "plaintext_hex": hex::encode(&plaintext3),
        "aad_hex": "",
        "expected_ciphertext_hex": hex::encode(&ct3),
    }));

    // Different key
    let key4 = [0x55_u8; 32];
    let nonce4 = [0xFF_u8; 12];
    let plaintext4 = b"medication data";
    let ct4 = aes_gcm_encrypt_explicit(&key4, &nonce4, plaintext4, b"");
    result.push(json!({
        "description": "Different key and nonce, medium plaintext",
        "key_hex": hex::encode(key4),
        "nonce_hex": hex::encode(nonce4),
        "plaintext_hex": hex::encode(plaintext4),
        "aad_hex": "",
        "expected_ciphertext_hex": hex::encode(&ct4),
    }));

    Value::Array(result)
}

// ── Key wrapping ────────────────────────────────────────────────────────────

fn generate_keywrap() -> Value {
    let wrapping_key = [0xCC_u8; 32];
    let key_to_wrap = [0xDD_u8; 32];
    let nonce = [0x10_u8; 12];

    let mut result = Vec::new();

    // Vault key wrapping
    let wrapped = aes_gcm_encrypt_explicit(
        &wrapping_key,
        &nonce,
        &key_to_wrap,
        b"pildora:v1:wrapped-vault-key",
    );
    result.push(json!({
        "description": "Wrap vault key",
        "wrapping_key_hex": hex::encode(wrapping_key),
        "key_to_wrap_hex": hex::encode(key_to_wrap),
        "aad": "pildora:v1:wrapped-vault-key",
        "nonce_hex": hex::encode(nonce),
        "expected_wrapped_hex": hex::encode(&wrapped),
    }));

    // Item key wrapping
    let nonce2 = [0x20_u8; 12];
    let item_key = [0xEE_u8; 32];
    let vault_key_as_wrapper = [0xFF_u8; 32];
    let wrapped2 = aes_gcm_encrypt_explicit(
        &vault_key_as_wrapper,
        &nonce2,
        &item_key,
        b"pildora:v1:wrapped-item-key",
    );
    result.push(json!({
        "description": "Wrap item key",
        "wrapping_key_hex": hex::encode(vault_key_as_wrapper),
        "key_to_wrap_hex": hex::encode(item_key),
        "aad": "pildora:v1:wrapped-item-key",
        "nonce_hex": hex::encode(nonce2),
        "expected_wrapped_hex": hex::encode(&wrapped2),
    }));

    Value::Array(result)
}

// ── BLAKE2b ─────────────────────────────────────────────────────────────────

fn generate_blake2b() -> Value {
    let mut result = Vec::new();

    // Hash empty input
    let hash_empty = primitives::blake2b_hash(b"");
    result.push(json!({
        "description": "Hash empty input",
        "input_hex": "",
        "expected_hash_hex": hex::encode(hash_empty),
    }));

    // Hash short input
    let hash_abc = primitives::blake2b_hash(b"abc");
    result.push(json!({
        "description": "Hash 'abc'",
        "input_hex": hex::encode(b"abc"),
        "expected_hash_hex": hex::encode(hash_abc),
    }));

    // Hash 256 bytes
    let data = vec![0x42_u8; 256];
    let hash256 = primitives::blake2b_hash(&data);
    result.push(json!({
        "description": "Hash 256 bytes of 0x42",
        "input_hex": hex::encode(&data),
        "expected_hash_hex": hex::encode(hash256),
    }));

    // Keyed hash
    let key = [0xAA_u8; 32];
    let mac = primitives::blake2b_mac(&key, b"keyed data").expect("BLAKE2b MAC failed");
    result.push(json!({
        "description": "Keyed hash (MAC)",
        "key_hex": hex::encode(key),
        "input_hex": hex::encode(b"keyed data"),
        "expected_hash_hex": hex::encode(mac),
    }));

    // Keyed hash with empty input
    let mac_empty = primitives::blake2b_mac(&key, b"").expect("BLAKE2b MAC failed");
    result.push(json!({
        "description": "Keyed hash (MAC) with empty input",
        "key_hex": hex::encode(key),
        "input_hex": "",
        "expected_hash_hex": hex::encode(mac_empty),
    }));

    Value::Array(result)
}

// ── Key hierarchy ───────────────────────────────────────────────────────────

fn generate_key_hierarchy() -> Value {
    let cases: Vec<(&str, &[u8], &[u8])> = vec![
        (
            "Full derivation: password → MK → auth_key + MEK",
            b"correct horse battery staple",
            b"saltsaltsaltsalt",
        ),
        (
            "Full derivation: simple password",
            b"password",
            b"somesalt12345678",
        ),
    ];

    cases
        .into_iter()
        .map(|(desc, password, salt)| {
            let mk = key_hierarchy::derive_master_key(password, salt)
                .expect("master key derivation failed");
            let (auth, mek) =
                key_hierarchy::derive_sub_keys(&mk).expect("sub-key derivation failed");
            json!({
                "description": desc,
                "password_hex": hex::encode(password),
                "salt_hex": hex::encode(salt),
                "expected_mk_hex": hex::encode(mk.as_bytes()),
                "expected_auth_key_hex": hex::encode(auth.as_bytes()),
                "expected_mek_hex": hex::encode(mek.as_bytes()),
            })
        })
        .collect()
}

// ── Item encryption (golden blobs) ──────────────────────────────────────────

fn generate_item_encryption() -> Value {
    let vault_key_bytes = [0x11_u8; 32];
    let vk = key_hierarchy::VaultKey::from_bytes(vault_key_bytes);

    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("Short plaintext (10 bytes)", vec![0x42_u8; 10]),
        ("Medium plaintext (500 bytes)", vec![0xAB_u8; 500]),
        ("Plaintext at 2KiB bucket boundary", vec![0xCD_u8; 1900]),
        ("Large plaintext (8000 bytes)", vec![0xEF_u8; 8000]),
    ];

    cases
        .into_iter()
        .map(|(desc, plaintext)| {
            let blob = vault::item_encrypt(&plaintext, &vk).expect("item_encrypt failed");
            json!({
                "description": desc,
                "vault_key_hex": hex::encode(vault_key_bytes),
                "plaintext_hex": hex::encode(&plaintext),
                "blob_hex": hex::encode(blob.to_bytes()),
                "blob_version": 1,
            })
        })
        .collect()
}
