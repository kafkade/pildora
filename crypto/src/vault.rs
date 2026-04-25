//! Item-level encryption and decryption.
//!
//! Provides the high-level API that CLI, iOS, and web call directly to
//! encrypt and decrypt vault items (medications, dose logs, schedules, etc.).
//!
//! ## Encrypted Blob Format (v1)
//!
//! ```text
//! [version: 1][nonce: 12][ciphertext: var][tag: 16][wrapped_item_key: 60]
//! ```
//!
//! - **version** — enables future schema migrations on the client side.
//! - **nonce + ciphertext + tag** — AES-256-GCM output from encrypting the
//!   padded plaintext with a per-item key.
//! - **wrapped item key** — the random item key, wrapped by the vault key.
//!
//! ## Padding
//!
//! Final blob sizes are padded to fixed-size buckets (512 B, 2 KiB, 8 KiB,
//! 32 KiB) to prevent size-based inference about the encrypted content.
//! The plaintext is prefixed with its original length (4 bytes, little-endian)
//! and zero-padded so the entire blob lands in the target bucket.
//! Items that exceed the largest bucket are stored without padding.

use serde::{Serialize, de::DeserializeOwned};
use zeroize::Zeroize;

use crate::error::{CryptoError, Result};
use crate::key_hierarchy::{self, VaultKey, WrappedItemKey};
use crate::primitives::{self, NONCE_LEN, TAG_LEN, WRAPPED_KEY_LEN};

/// Vault identifier type.
pub type VaultId = uuid::Uuid;

// ── Blob constants ───────────────────────────────────────────────────────────

/// Encrypted blob version byte.
const BLOB_VERSION: u8 = crate::BLOB_VERSION;

/// Fixed overhead in every blob: version + nonce + tag + wrapped item key.
const BLOB_OVERHEAD: usize = 1 + NONCE_LEN + TAG_LEN + WRAPPED_KEY_LEN;

/// Length prefix for the original plaintext (u32 little-endian).
const LENGTH_PREFIX: usize = 4;

/// Padding size buckets for the **final blob** (not plaintext).
const SIZE_BUCKETS: &[usize] = &[512, 2048, 8192, 32768];

/// AAD used for item encryption (domain separation).
const AAD_ITEM_BLOB: &[u8] = b"pildora:v1:item-blob";

// ── `EncryptedBlob` ──────────────────────────────────────────────────────────

/// An encrypted item blob ready for storage or sync.
///
/// The blob is self-contained: it carries the wrapped item key so that only the
/// vault key is needed to decrypt it.
#[derive(Clone, Debug)]
pub struct EncryptedBlob {
    data: Vec<u8>,
}

impl EncryptedBlob {
    /// Minimum valid blob size: version + nonce + tag + wrapped key.
    const MIN_LEN: usize = BLOB_OVERHEAD;

    /// Serialize the blob to its wire representation.
    #[must_use]
    pub fn to_bytes(&self) -> &[u8] {
        &self.data
    }

    /// Deserialize a blob from its wire representation.
    pub fn from_bytes(data: Vec<u8>) -> Result<Self> {
        if data.len() < Self::MIN_LEN {
            return Err(CryptoError::Decryption("blob too short".into()));
        }
        if data[0] != BLOB_VERSION {
            return Err(CryptoError::UnsupportedBlobVersion { version: data[0] });
        }
        Ok(Self { data })
    }

    /// The blob version byte.
    #[must_use]
    pub fn version(&self) -> u8 {
        self.data[0]
    }

    /// Total size in bytes.
    #[must_use]
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Whether the blob is empty (always false for valid blobs).
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
}

// ── Core encrypt / decrypt ───────────────────────────────────────────────────

/// Encrypt arbitrary plaintext into an [`EncryptedBlob`].
///
/// Generates a random per-item key, encrypts the padded plaintext, wraps the
/// item key with the vault key, and assembles the blob.
pub fn item_encrypt(plaintext: &[u8], vault_key: &VaultKey) -> Result<EncryptedBlob> {
    if plaintext.len() > u32::MAX as usize {
        return Err(CryptoError::Encryption(
            "plaintext exceeds maximum size (4 GiB)".into(),
        ));
    }

    // Generate random item key
    let ik = key_hierarchy::generate_item_key();

    // Pad plaintext with length prefix
    let padded = pad_plaintext(plaintext);

    // Encrypt padded plaintext with item key
    let encrypted = primitives::aes256_gcm_encrypt(ik.as_bytes(), &padded, AAD_ITEM_BLOB)?;

    // Wrap item key with vault key
    let wrapped_ik = key_hierarchy::wrap_item_key(&ik, vault_key)?;

    // Assemble blob: version || encrypted || wrapped_ik
    let blob_len = 1 + encrypted.len() + WRAPPED_KEY_LEN;
    let mut data = Vec::with_capacity(blob_len);
    data.push(BLOB_VERSION);
    data.extend_from_slice(&encrypted);
    data.extend_from_slice(&wrapped_ik.0);

    Ok(EncryptedBlob { data })
}

/// Decrypt an [`EncryptedBlob`] back to plaintext.
pub fn item_decrypt(blob: &EncryptedBlob, vault_key: &VaultKey) -> Result<Vec<u8>> {
    let data = &blob.data;

    // Check version
    if data[0] != BLOB_VERSION {
        return Err(CryptoError::UnsupportedBlobVersion { version: data[0] });
    }

    // Split: version (1) || encrypted (...) || wrapped_ik (60)
    let encrypted_end = data.len() - WRAPPED_KEY_LEN;
    let encrypted = &data[1..encrypted_end];
    let wrapped_ik_bytes = &data[encrypted_end..];

    // Unwrap item key
    let wrapped_ik = WrappedItemKey(wrapped_ik_bytes.to_vec());
    let ik = key_hierarchy::unwrap_item_key(&wrapped_ik, vault_key)?;

    // Decrypt
    let mut padded = primitives::aes256_gcm_decrypt(ik.as_bytes(), encrypted, AAD_ITEM_BLOB)?;

    // Unpad
    let result = unpad_plaintext(&padded)?;
    padded.zeroize();

    Ok(result)
}

// ── Typed JSON encryption helpers ────────────────────────────────────────────

/// Encrypt a serializable value as JSON inside an [`EncryptedBlob`].
pub fn encrypt_json<T: Serialize>(value: &T, vault_key: &VaultKey) -> Result<EncryptedBlob> {
    let json = serde_json::to_vec(value).map_err(|e| CryptoError::Serialization(e.to_string()))?;
    item_encrypt(&json, vault_key)
}

/// Decrypt an [`EncryptedBlob`] and deserialize the JSON payload.
pub fn decrypt_json<T: DeserializeOwned>(blob: &EncryptedBlob, vault_key: &VaultKey) -> Result<T> {
    let mut plaintext = item_decrypt(blob, vault_key)?;
    let result =
        serde_json::from_slice(&plaintext).map_err(|e| CryptoError::Serialization(e.to_string()));
    plaintext.zeroize();
    result
}

// ── Padding ──────────────────────────────────────────────────────────────────

/// Choose the target padded-plaintext size so the final blob fits in a bucket.
fn target_padded_size(plaintext_len: usize) -> usize {
    let needed_blob = BLOB_OVERHEAD + LENGTH_PREFIX + plaintext_len;
    for &bucket in SIZE_BUCKETS {
        if needed_blob <= bucket {
            // Padded plaintext = bucket - overhead (version + nonce + tag + wrapped_key)
            return bucket - BLOB_OVERHEAD;
        }
    }
    // Larger than all buckets — no padding, just length-prefix
    LENGTH_PREFIX + plaintext_len
}

/// Prepend a 4-byte length prefix and zero-pad to the target size.
fn pad_plaintext(plaintext: &[u8]) -> Vec<u8> {
    let target = target_padded_size(plaintext.len());
    // Safe: max plaintext is bounded by bucket sizes (<= ~32KB for padded,
    // and items >4GB would exhaust memory long before reaching this code.
    #[allow(clippy::cast_possible_truncation)]
    let len_bytes = (plaintext.len() as u32).to_le_bytes();
    let mut padded = Vec::with_capacity(target);
    padded.extend_from_slice(&len_bytes);
    padded.extend_from_slice(plaintext);
    padded.resize(target, 0);
    padded
}

/// Remove padding and extract original plaintext.
fn unpad_plaintext(padded: &[u8]) -> Result<Vec<u8>> {
    if padded.len() < LENGTH_PREFIX {
        return Err(CryptoError::Decryption("padded data too short".into()));
    }

    let len = u32::from_le_bytes([padded[0], padded[1], padded[2], padded[3]]) as usize;
    if LENGTH_PREFIX + len > padded.len() {
        return Err(CryptoError::Decryption("invalid plaintext length".into()));
    }

    Ok(padded[LENGTH_PREFIX..LENGTH_PREFIX + len].to_vec())
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::key_hierarchy::generate_vault_key;

    // ── Helper domain types for testing ──────────────────────────────────

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, serde::Deserialize)]
    struct Medication {
        name: String,
        dosage: String,
        frequency: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, serde::Deserialize)]
    struct DoseLog {
        medication_id: String,
        taken_at: String,
        notes: Option<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, serde::Deserialize)]
    struct Schedule {
        medication_id: String,
        times: Vec<String>,
        days: Vec<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, serde::Deserialize)]
    struct Inventory {
        medication_id: String,
        count: u32,
        refill_date: Option<String>,
    }

    // ── Basic roundtrip ──────────────────────────────────────────────────

    #[test]
    fn encrypt_decrypt_roundtrip_empty() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"", &vk).unwrap();
        let pt = item_decrypt(&blob, &vk).unwrap();
        assert!(pt.is_empty());
    }

    #[test]
    fn encrypt_decrypt_roundtrip_small() {
        let vk = generate_vault_key();
        let data = b"hello, world!";
        let blob = item_encrypt(data, &vk).unwrap();
        let pt = item_decrypt(&blob, &vk).unwrap();
        assert_eq!(pt, data);
    }

    #[test]
    fn encrypt_decrypt_roundtrip_1kb() {
        let vk = generate_vault_key();
        let data = vec![0xAB; 1024];
        let blob = item_encrypt(&data, &vk).unwrap();
        let pt = item_decrypt(&blob, &vk).unwrap();
        assert_eq!(pt, data);
    }

    #[test]
    fn encrypt_decrypt_roundtrip_large() {
        let vk = generate_vault_key();
        let data = vec![0xCD; 40_000]; // Exceeds all buckets
        let blob = item_encrypt(&data, &vk).unwrap();
        let pt = item_decrypt(&blob, &vk).unwrap();
        assert_eq!(pt, data);
    }

    // ── Ciphertext uniqueness ────────────────────────────────────────────

    #[test]
    fn two_encryptions_differ() {
        let vk = generate_vault_key();
        let blob1 = item_encrypt(b"same data", &vk).unwrap();
        let blob2 = item_encrypt(b"same data", &vk).unwrap();
        assert_ne!(
            blob1.to_bytes(),
            blob2.to_bytes(),
            "random nonce + random IK must produce different blobs"
        );
    }

    // ── Tamper detection ─────────────────────────────────────────────────

    #[test]
    fn tamper_ciphertext_fails() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"sensitive", &vk).unwrap();
        let mut data = blob.data.clone();
        // Flip a byte in the ciphertext area (after version + nonce)
        data[NONCE_LEN + 3] ^= 0xFF;
        let tampered = EncryptedBlob { data };
        assert!(item_decrypt(&tampered, &vk).is_err());
    }

    #[test]
    fn tamper_wrapped_key_fails() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"sensitive", &vk).unwrap();
        let mut data = blob.data.clone();
        // Flip a byte in the wrapped key area
        let last = data.len() - 1;
        data[last] ^= 0xFF;
        let tampered = EncryptedBlob { data };
        assert!(item_decrypt(&tampered, &vk).is_err());
    }

    #[test]
    fn wrong_vault_key_fails() {
        let vk1 = generate_vault_key();
        let vk2 = generate_vault_key();
        let blob = item_encrypt(b"secret", &vk1).unwrap();
        assert!(item_decrypt(&blob, &vk2).is_err());
    }

    // ── Blob version ─────────────────────────────────────────────────────

    #[test]
    fn blob_version_is_1() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"test", &vk).unwrap();
        assert_eq!(blob.version(), 1);
    }

    #[test]
    fn blob_wrong_version_rejected() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"test", &vk).unwrap();
        let mut data = blob.data.clone();
        data[0] = 99;
        let result = EncryptedBlob::from_bytes(data);
        assert!(result.is_err());
    }

    #[test]
    fn blob_too_short_rejected() {
        let result = EncryptedBlob::from_bytes(vec![1, 2, 3]);
        assert!(result.is_err());
    }

    // ── Blob serialization roundtrip ─────────────────────────────────────

    #[test]
    fn blob_bytes_roundtrip() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"roundtrip", &vk).unwrap();
        let bytes = blob.to_bytes().to_vec();
        let restored = EncryptedBlob::from_bytes(bytes).unwrap();
        let pt = item_decrypt(&restored, &vk).unwrap();
        assert_eq!(pt, b"roundtrip");
    }

    // ── Padding ──────────────────────────────────────────────────────────

    #[test]
    fn padding_small_fits_512_bucket() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"small", &vk).unwrap();
        assert_eq!(blob.len(), 512);
    }

    #[test]
    fn padding_empty_fits_512_bucket() {
        let vk = generate_vault_key();
        let blob = item_encrypt(b"", &vk).unwrap();
        assert_eq!(blob.len(), 512);
    }

    #[test]
    fn padding_medium_fits_2kb_bucket() {
        let vk = generate_vault_key();
        // 512 - 89 - 4 = 419 max plaintext for 512 bucket
        let data = vec![0xAA; 420]; // Just over → should bump to 2KB
        let blob = item_encrypt(&data, &vk).unwrap();
        assert_eq!(blob.len(), 2048);
    }

    #[test]
    fn padding_8kb_bucket() {
        let vk = generate_vault_key();
        // 2048 - 89 - 4 = 1955 max for 2KB bucket
        let data = vec![0xBB; 1956];
        let blob = item_encrypt(&data, &vk).unwrap();
        assert_eq!(blob.len(), 8192);
    }

    #[test]
    fn padding_32kb_bucket() {
        let vk = generate_vault_key();
        // 8192 - 89 - 4 = 8099 max for 8KB bucket
        let data = vec![0xCC; 8100];
        let blob = item_encrypt(&data, &vk).unwrap();
        assert_eq!(blob.len(), 32768);
    }

    #[test]
    fn padding_exceeds_all_buckets_no_padding() {
        let vk = generate_vault_key();
        // 32768 - 89 - 4 = 32675 max for 32KB bucket
        let data = vec![0xDD; 32676];
        let blob = item_encrypt(&data, &vk).unwrap();
        // No bucket padding — exact size
        let expected = 1 + NONCE_LEN + LENGTH_PREFIX + data.len() + TAG_LEN + WRAPPED_KEY_LEN;
        assert_eq!(blob.len(), expected);
    }

    #[test]
    fn padding_preserves_data() {
        let vk = generate_vault_key();
        for size in [
            0, 1, 100, 419, 420, 1955, 1956, 8099, 8100, 32675, 32676, 50_000,
        ] {
            let data = vec![0xEE; size];
            let blob = item_encrypt(&data, &vk).unwrap();
            let pt = item_decrypt(&blob, &vk).unwrap();
            assert_eq!(pt.len(), size, "roundtrip failed for size {size}");
            assert_eq!(pt, data, "data mismatch for size {size}");
        }
    }

    #[test]
    fn all_blobs_in_correct_buckets() {
        let vk = generate_vault_key();
        let valid_sizes = [512, 2048, 8192, 32768];
        for size in [0, 1, 50, 200, 419] {
            let blob = item_encrypt(&vec![0; size], &vk).unwrap();
            assert!(
                valid_sizes.contains(&blob.len()),
                "blob len {} not in buckets for plaintext size {size}",
                blob.len()
            );
        }
    }

    // ── Typed JSON encryption ────────────────────────────────────────────

    #[test]
    fn encrypt_medication_roundtrip() {
        let vk = generate_vault_key();
        let med = Medication {
            name: "Lisinopril".into(),
            dosage: "10mg".into(),
            frequency: "daily".into(),
        };
        let blob = encrypt_json(&med, &vk).unwrap();
        let decrypted: Medication = decrypt_json(&blob, &vk).unwrap();
        assert_eq!(med, decrypted);
    }

    #[test]
    fn encrypt_dose_log_roundtrip() {
        let vk = generate_vault_key();
        let log = DoseLog {
            medication_id: "med-001".into(),
            taken_at: "2026-04-25T10:30:00Z".into(),
            notes: Some("Taken with food".into()),
        };
        let blob = encrypt_json(&log, &vk).unwrap();
        let decrypted: DoseLog = decrypt_json(&blob, &vk).unwrap();
        assert_eq!(log, decrypted);
    }

    #[test]
    fn encrypt_schedule_roundtrip() {
        let vk = generate_vault_key();
        let schedule = Schedule {
            medication_id: "med-002".into(),
            times: vec!["08:00".into(), "20:00".into()],
            days: vec!["Mon".into(), "Wed".into(), "Fri".into()],
        };
        let blob = encrypt_json(&schedule, &vk).unwrap();
        let decrypted: Schedule = decrypt_json(&blob, &vk).unwrap();
        assert_eq!(schedule, decrypted);
    }

    #[test]
    fn encrypt_inventory_roundtrip() {
        let vk = generate_vault_key();
        let inv = Inventory {
            medication_id: "med-003".into(),
            count: 28,
            refill_date: Some("2026-05-15".into()),
        };
        let blob = encrypt_json(&inv, &vk).unwrap();
        let decrypted: Inventory = decrypt_json(&blob, &vk).unwrap();
        assert_eq!(inv, decrypted);
    }

    #[test]
    fn encrypt_json_wrong_key_fails() {
        let vk1 = generate_vault_key();
        let vk2 = generate_vault_key();
        let med = Medication {
            name: "Secret Med".into(),
            dosage: "5mg".into(),
            frequency: "daily".into(),
        };
        let blob = encrypt_json(&med, &vk1).unwrap();
        let result: Result<Medication> = decrypt_json(&blob, &vk2);
        assert!(result.is_err());
    }

    // ── Internal padding helpers ─────────────────────────────────────────

    #[test]
    fn pad_unpad_roundtrip() {
        for size in [0, 1, 10, 100, 1000, 10_000, 50_000] {
            let data = vec![0xFF; size];
            let padded = pad_plaintext(&data);
            let unpadded = unpad_plaintext(&padded).unwrap();
            assert_eq!(unpadded, data, "pad/unpad failed for size {size}");
        }
    }

    #[test]
    fn unpad_too_short_fails() {
        assert!(unpad_plaintext(&[1, 2, 3]).is_err());
    }

    #[test]
    fn unpad_invalid_length_fails() {
        // Claim length of 100 but only 4 bytes of padding data
        let mut data = vec![0; 8];
        data[..4].copy_from_slice(&100u32.to_le_bytes());
        assert!(unpad_plaintext(&data).is_err());
    }
}
