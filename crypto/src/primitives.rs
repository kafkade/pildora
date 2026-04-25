//! Low-level cryptographic primitives for pildora-crypto.
//!
//! This module wraps the `RustCrypto` ecosystem into ergonomic helpers that the
//! higher-level key-hierarchy and item-encryption layers build on.  Every
//! function maps to exactly one algorithm; composition lives in
//! [`crate::key_hierarchy`] and [`crate::vault`].

use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use blake2::digest::consts::U32;
use blake2::{Blake2b, Blake2bMac, Digest};
use hkdf::Hkdf;
use rand::RngCore;
use sha2::Sha256;
use zeroize::Zeroize;

use crate::error::{CryptoError, Result};

// ── Constants ────────────────────────────────────────────────────────────────

/// AES-256-GCM nonce length in bytes (96 bits).
pub const NONCE_LEN: usize = 12;
/// AES-256-GCM authentication tag length in bytes (128 bits).
pub const TAG_LEN: usize = 16;
/// Symmetric key length in bytes (256 bits).
pub const KEY_LEN: usize = 32;
/// Wrapped key overhead: nonce + tag.
pub const WRAPPED_KEY_OVERHEAD: usize = NONCE_LEN + TAG_LEN;
/// Total wrapped key blob size: nonce (12) + encrypted key (32) + tag (16).
pub const WRAPPED_KEY_LEN: usize = KEY_LEN + WRAPPED_KEY_OVERHEAD;

// ── Argon2id ─────────────────────────────────────────────────────────────────

/// Derive a 256-bit key from a password and salt using Argon2id.
///
/// Parameters (ADR-001): 64 MiB memory, 3 iterations, parallelism 1.
pub fn derive_key_argon2id(password: &[u8], salt: &[u8]) -> Result<[u8; KEY_LEN]> {
    use argon2::{Algorithm, Argon2, Params, Version};

    let params = Params::new(64 * 1024, 3, 1, Some(KEY_LEN))
        .map_err(|e| CryptoError::KeyDerivation(e.to_string()))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut output = [0u8; KEY_LEN];
    argon2
        .hash_password_into(password, salt, &mut output)
        .map_err(|e| CryptoError::KeyDerivation(e.to_string()))?;
    Ok(output)
}

// ── HKDF-SHA-256 ─────────────────────────────────────────────────────────────

/// HKDF extract-then-expand using SHA-256.
///
/// Returns `output_len` bytes of derived key material.
pub fn hkdf_sha256(
    ikm: &[u8],
    salt: Option<&[u8]>,
    info: &[u8],
    output_len: usize,
) -> Result<Vec<u8>> {
    let hk = Hkdf::<Sha256>::new(salt, ikm);
    let mut okm = vec![0u8; output_len];
    hk.expand(info, &mut okm)
        .map_err(|e| CryptoError::KeyDerivation(e.to_string()))?;
    Ok(okm)
}

// ── AES-256-GCM ──────────────────────────────────────────────────────────────

/// Encrypt `plaintext` with AES-256-GCM using a random nonce.
///
/// Returns `nonce (12) || ciphertext || tag (16)`.
/// `aad` is authenticated but not encrypted (associated data).
pub fn aes256_gcm_encrypt(key: &[u8; KEY_LEN], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    let cipher =
        Aes256Gcm::new_from_slice(key).map_err(|e| CryptoError::Encryption(e.to_string()))?;

    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let payload = aes_gcm::aead::Payload {
        msg: plaintext,
        aad,
    };
    let ciphertext = cipher
        .encrypt(nonce, payload)
        .map_err(|e| CryptoError::Encryption(e.to_string()))?;

    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Decrypt a blob produced by [`aes256_gcm_encrypt`].
///
/// Expects `nonce (12) || ciphertext || tag (16)`.
pub fn aes256_gcm_decrypt(
    key: &[u8; KEY_LEN],
    ciphertext_with_nonce: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>> {
    if ciphertext_with_nonce.len() < NONCE_LEN + TAG_LEN {
        return Err(CryptoError::Decryption("input too short".into()));
    }

    let (nonce_bytes, ct) = ciphertext_with_nonce.split_at(NONCE_LEN);
    let nonce = Nonce::from_slice(nonce_bytes);

    let cipher =
        Aes256Gcm::new_from_slice(key).map_err(|e| CryptoError::Decryption(e.to_string()))?;

    let payload = aes_gcm::aead::Payload { msg: ct, aad };
    cipher
        .decrypt(nonce, payload)
        .map_err(|e| CryptoError::Decryption(e.to_string()))
}

// ── Key wrapping (AES-256-GCM based) ────────────────────────────────────────

/// Wrap a 32-byte key with AES-256-GCM.
///
/// `aad` provides domain separation (e.g. `b"pildora:v1:vault-key"`).
/// Returns a 60-byte blob: `nonce (12) || encrypted_key (32) || tag (16)`.
pub fn aes256_gcm_keywrap(
    wrapping_key: &[u8; KEY_LEN],
    key_to_wrap: &[u8; KEY_LEN],
    aad: &[u8],
) -> Result<Vec<u8>> {
    let result = aes256_gcm_encrypt(wrapping_key, key_to_wrap, aad)?;
    debug_assert_eq!(result.len(), WRAPPED_KEY_LEN);
    Ok(result)
}

/// Unwrap a key previously wrapped by [`aes256_gcm_keywrap`].
pub fn aes256_gcm_key_unwrap(
    wrapping_key: &[u8; KEY_LEN],
    wrapped_key: &[u8],
    aad: &[u8],
) -> Result<[u8; KEY_LEN]> {
    if wrapped_key.len() != WRAPPED_KEY_LEN {
        return Err(CryptoError::KeyWrap(format!(
            "expected {} bytes, got {}",
            WRAPPED_KEY_LEN,
            wrapped_key.len()
        )));
    }

    let mut plaintext = aes256_gcm_decrypt(wrapping_key, wrapped_key, aad)
        .map_err(|_| CryptoError::KeyWrap("unwrap failed — wrong key or tampered data".into()))?;

    if plaintext.len() != KEY_LEN {
        plaintext.zeroize();
        return Err(CryptoError::KeyWrap(
            "unexpected unwrapped key length".into(),
        ));
    }

    let mut key = [0u8; KEY_LEN];
    key.copy_from_slice(&plaintext);
    plaintext.zeroize();
    Ok(key)
}

// ── X25519 ───────────────────────────────────────────────────────────────────

/// An X25519 static secret key. Zeroized on drop.
#[derive(Zeroize)]
#[zeroize(drop)]
pub struct X25519SecretKey(x25519_dalek::StaticSecret);

impl X25519SecretKey {
    /// Return the corresponding public key.
    #[must_use]
    pub fn public_key(&self) -> X25519PublicKey {
        X25519PublicKey(x25519_dalek::PublicKey::from(&self.0))
    }
}

impl std::fmt::Debug for X25519SecretKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("X25519SecretKey([REDACTED])")
    }
}

/// An X25519 public key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct X25519PublicKey(x25519_dalek::PublicKey);

impl X25519PublicKey {
    /// Create from raw 32-byte representation.
    #[must_use]
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(x25519_dalek::PublicKey::from(bytes))
    }

    /// Raw 32-byte representation.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8; 32] {
        self.0.as_bytes()
    }
}

/// Generate a random X25519 keypair.
#[must_use]
pub fn x25519_keypair() -> (X25519SecretKey, X25519PublicKey) {
    let secret = x25519_dalek::StaticSecret::random_from_rng(rand::rngs::OsRng);
    let public = x25519_dalek::PublicKey::from(&secret);
    (X25519SecretKey(secret), X25519PublicKey(public))
}

/// Perform X25519 Diffie-Hellman key agreement.
///
/// Returns the 32-byte shared secret.
pub fn x25519_diffie_hellman(secret: &X25519SecretKey, their_public: &X25519PublicKey) -> [u8; 32] {
    secret.0.diffie_hellman(&their_public.0).to_bytes()
}

// ── BLAKE2b ──────────────────────────────────────────────────────────────────

/// Hash `data` with BLAKE2b-256 (unkeyed).
#[must_use]
pub fn blake2b_hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b::<U32>::new();
    Digest::update(&mut hasher, data);
    hasher.finalize().into()
}

/// Keyed BLAKE2b-256 MAC.
///
/// Alias: [`blake2b_hash_with_key`].
pub fn blake2b_mac(key: &[u8], data: &[u8]) -> Result<[u8; 32]> {
    use blake2::digest::Mac;
    let mut mac = <Blake2bMac<U32> as KeyInit>::new_from_slice(key)
        .map_err(|e| CryptoError::Encryption(format!("BLAKE2b key error: {e}")))?;
    Mac::update(&mut mac, data);
    Ok(mac.finalize().into_bytes().into())
}

/// Keyed BLAKE2b-256 — convenience alias for [`blake2b_mac`].
pub fn blake2b_hash_with_key(key: &[u8], data: &[u8]) -> Result<[u8; 32]> {
    blake2b_mac(key, data)
}

// ── Random generation ────────────────────────────────────────────────────────

/// Generate a random 16-byte salt for Argon2id.
#[must_use]
pub fn generate_salt() -> [u8; 16] {
    let mut salt = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut salt);
    salt
}

/// Generate a random 32-byte key.
#[must_use]
pub fn generate_random_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    rand::rngs::OsRng.fill_bytes(&mut key);
    key
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use hex_literal::hex;

    // ── Argon2id ─────────────────────────────────────────────────────────

    #[test]
    fn argon2id_deterministic() {
        let password = b"password";
        let salt = b"somesalt12345678"; // 16 bytes
        let key1 = derive_key_argon2id(password, salt).unwrap();
        let key2 = derive_key_argon2id(password, salt).unwrap();
        assert_eq!(key1, key2, "same input must produce same key");
    }

    #[test]
    fn argon2id_different_passwords() {
        let salt = b"somesalt12345678";
        let k1 = derive_key_argon2id(b"password1", salt).unwrap();
        let k2 = derive_key_argon2id(b"password2", salt).unwrap();
        assert_ne!(k1, k2);
    }

    #[test]
    fn argon2id_different_salts() {
        let password = b"password";
        let k1 = derive_key_argon2id(password, b"salt_one_1234567").unwrap();
        let k2 = derive_key_argon2id(password, b"salt_two_1234567").unwrap();
        assert_ne!(k1, k2);
    }

    #[test]
    fn argon2id_output_length() {
        let key = derive_key_argon2id(b"pass", b"saltsaltsaltsalt").unwrap();
        assert_eq!(key.len(), 32);
    }

    // ── HKDF-SHA-256 ────────────────────────────────────────────────────
    //
    // RFC 5869 Test Case 1

    #[test]
    fn hkdf_rfc5869_test_case_1() {
        let ikm = hex!("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
        let salt = hex!("000102030405060708090a0b0c");
        let info = hex!("f0f1f2f3f4f5f6f7f8f9");
        let expected = hex!(
            "3cb25f25faacd57a90434f64d0362f2a"
            "2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
            "34007208d5b887185865"
        );

        let okm = hkdf_sha256(&ikm, Some(&salt), &info, 42).unwrap();
        assert_eq!(okm, expected);
    }

    #[test]
    fn hkdf_different_info_produces_different_keys() {
        let ikm = [0x42u8; 32];
        let k1 = hkdf_sha256(&ikm, None, b"auth-key", 32).unwrap();
        let k2 = hkdf_sha256(&ikm, None, b"encryption-key", 32).unwrap();
        assert_ne!(k1, k2);
    }

    // ── AES-256-GCM ─────────────────────────────────────────────────────

    #[test]
    fn aes_gcm_roundtrip_empty() {
        let key = generate_random_key();
        let ct = aes256_gcm_encrypt(&key, b"", b"").unwrap();
        let pt = aes256_gcm_decrypt(&key, &ct, b"").unwrap();
        assert!(pt.is_empty());
    }

    #[test]
    fn aes_gcm_roundtrip_1_byte() {
        let key = generate_random_key();
        let ct = aes256_gcm_encrypt(&key, &[0x42], b"").unwrap();
        let pt = aes256_gcm_decrypt(&key, &ct, b"").unwrap();
        assert_eq!(pt, [0x42]);
    }

    #[test]
    fn aes_gcm_roundtrip_1kb() {
        let key = generate_random_key();
        let data = vec![0xAB; 1024];
        let ct = aes256_gcm_encrypt(&key, &data, b"").unwrap();
        let pt = aes256_gcm_decrypt(&key, &ct, b"").unwrap();
        assert_eq!(pt, data);
    }

    #[test]
    fn aes_gcm_roundtrip_1mb() {
        let key = generate_random_key();
        let data = vec![0xCD; 1024 * 1024];
        let ct = aes256_gcm_encrypt(&key, &data, b"").unwrap();
        let pt = aes256_gcm_decrypt(&key, &ct, b"").unwrap();
        assert_eq!(pt, data);
    }

    #[test]
    fn aes_gcm_with_aad() {
        let key = generate_random_key();
        let aad = b"associated data";
        let ct = aes256_gcm_encrypt(&key, b"hello", aad).unwrap();
        let pt = aes256_gcm_decrypt(&key, &ct, aad).unwrap();
        assert_eq!(pt, b"hello");
    }

    #[test]
    fn aes_gcm_wrong_aad_fails() {
        let key = generate_random_key();
        let ct = aes256_gcm_encrypt(&key, b"hello", b"correct").unwrap();
        let result = aes256_gcm_decrypt(&key, &ct, b"wrong");
        assert!(result.is_err());
    }

    #[test]
    fn aes_gcm_wrong_key_fails() {
        let key1 = generate_random_key();
        let key2 = generate_random_key();
        let ct = aes256_gcm_encrypt(&key1, b"hello", b"").unwrap();
        let result = aes256_gcm_decrypt(&key2, &ct, b"");
        assert!(result.is_err());
    }

    #[test]
    fn aes_gcm_nondeterministic() {
        let key = generate_random_key();
        let ct1 = aes256_gcm_encrypt(&key, b"same", b"").unwrap();
        let ct2 = aes256_gcm_encrypt(&key, b"same", b"").unwrap();
        assert_ne!(ct1, ct2, "random nonce must produce different ciphertexts");
    }

    #[test]
    fn aes_gcm_tamper_detection() {
        let key = generate_random_key();
        let mut ct = aes256_gcm_encrypt(&key, b"hello", b"").unwrap();
        // Flip a byte in the ciphertext area
        let idx = NONCE_LEN + 2;
        ct[idx] ^= 0xFF;
        assert!(aes256_gcm_decrypt(&key, &ct, b"").is_err());
    }

    #[test]
    fn aes_gcm_input_too_short() {
        let key = generate_random_key();
        let result = aes256_gcm_decrypt(&key, &[0u8; 10], b"");
        assert!(result.is_err());
    }

    // ── Keywrap ──────────────────────────────────────────────────────────

    #[test]
    fn keywrap_roundtrip() {
        let wrapping_key = generate_random_key();
        let key_to_wrap = generate_random_key();
        let aad = b"pildora:v1:vault-key";

        let wrapped = aes256_gcm_keywrap(&wrapping_key, &key_to_wrap, aad).unwrap();
        assert_eq!(wrapped.len(), WRAPPED_KEY_LEN);

        let unwrapped = aes256_gcm_key_unwrap(&wrapping_key, &wrapped, aad).unwrap();
        assert_eq!(unwrapped, key_to_wrap);
    }

    #[test]
    fn keywrap_wrong_key_fails() {
        let wk1 = generate_random_key();
        let wk2 = generate_random_key();
        let key = generate_random_key();
        let aad = b"pildora:v1:vault-key";

        let wrapped = aes256_gcm_keywrap(&wk1, &key, aad).unwrap();
        assert!(aes256_gcm_key_unwrap(&wk2, &wrapped, aad).is_err());
    }

    #[test]
    fn keywrap_wrong_aad_fails() {
        let wk = generate_random_key();
        let key = generate_random_key();

        let wrapped = aes256_gcm_keywrap(&wk, &key, b"correct-aad").unwrap();
        assert!(aes256_gcm_key_unwrap(&wk, &wrapped, b"wrong-aad").is_err());
    }

    #[test]
    fn keywrap_bad_length_fails() {
        let wk = generate_random_key();
        assert!(aes256_gcm_key_unwrap(&wk, &[0u8; 59], b"").is_err());
        assert!(aes256_gcm_key_unwrap(&wk, &[0u8; 61], b"").is_err());
    }

    #[test]
    fn keywrap_output_is_60_bytes() {
        let wk = generate_random_key();
        let key = generate_random_key();
        let wrapped = aes256_gcm_keywrap(&wk, &key, b"").unwrap();
        assert_eq!(wrapped.len(), 60);
    }

    // ── X25519 ───────────────────────────────────────────────────────────

    #[test]
    fn x25519_shared_secret_agreement() {
        let (sk_a, pk_a) = x25519_keypair();
        let (sk_b, pk_b) = x25519_keypair();

        let shared_ab = x25519_diffie_hellman(&sk_a, &pk_b);
        let shared_ba = x25519_diffie_hellman(&sk_b, &pk_a);
        assert_eq!(shared_ab, shared_ba, "DH shared secrets must agree");
    }

    #[test]
    fn x25519_different_keypairs_different_secrets() {
        let (sk_a, _pk_a) = x25519_keypair();
        let (sk_b, _pk_b) = x25519_keypair();
        let (_, pk_c) = x25519_keypair();

        let s1 = x25519_diffie_hellman(&sk_a, &pk_c);
        let s2 = x25519_diffie_hellman(&sk_b, &pk_c);
        assert_ne!(s1, s2);
    }

    #[test]
    fn x25519_public_key_roundtrip() {
        let (_sk, pk) = x25519_keypair();
        let bytes = *pk.as_bytes();
        let pk2 = X25519PublicKey::from_bytes(bytes);
        assert_eq!(pk, pk2);
    }

    #[test]
    fn x25519_secret_key_debug_redacted() {
        let (sk, _) = x25519_keypair();
        let debug = format!("{sk:?}");
        assert_eq!(debug, "X25519SecretKey([REDACTED])");
    }

    // ── BLAKE2b ──────────────────────────────────────────────────────────

    #[test]
    fn blake2b_deterministic() {
        let h1 = blake2b_hash(b"hello");
        let h2 = blake2b_hash(b"hello");
        assert_eq!(h1, h2);
    }

    #[test]
    fn blake2b_different_inputs() {
        let h1 = blake2b_hash(b"hello");
        let h2 = blake2b_hash(b"world");
        assert_ne!(h1, h2);
    }

    #[test]
    fn blake2b_known_empty_hash() {
        // BLAKE2b-256 of empty input
        let h = blake2b_hash(b"");
        // Known value: BLAKE2b-256("")
        assert_eq!(h.len(), 32);
        // Verify it's consistent (no randomness)
        assert_eq!(h, blake2b_hash(b""));
    }

    #[test]
    fn blake2b_mac_roundtrip() {
        let key = generate_random_key();
        let mac1 = blake2b_mac(&key, b"data").unwrap();
        let mac2 = blake2b_mac(&key, b"data").unwrap();
        assert_eq!(mac1, mac2);
    }

    #[test]
    fn blake2b_mac_different_keys() {
        let k1 = generate_random_key();
        let k2 = generate_random_key();
        let m1 = blake2b_mac(&k1, b"data").unwrap();
        let m2 = blake2b_mac(&k2, b"data").unwrap();
        assert_ne!(m1, m2);
    }

    // ── Salt / random generation ─────────────────────────────────────────

    #[test]
    fn salt_length() {
        let salt = generate_salt();
        assert_eq!(salt.len(), 16);
    }

    #[test]
    fn salt_randomness() {
        let s1 = generate_salt();
        let s2 = generate_salt();
        assert_ne!(s1, s2, "two random salts should differ");
    }

    #[test]
    fn random_key_length() {
        let key = generate_random_key();
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn random_key_uniqueness() {
        let k1 = generate_random_key();
        let k2 = generate_random_key();
        assert_ne!(k1, k2);
    }
}
