//! Key hierarchy: master key derivation, sub-key derivation, and key
//! wrapping/unwrapping for vault and item keys.
//!
//! Implements the full key hierarchy from ADR-001:
//!
//! ```text
//! Master Password
//!     → [Argon2id + salt] → Master Key (MK)
//!         → [HKDF] → Authentication Key (for SRP)
//!         → [HKDF] → Master Encryption Key (MEK)
//!             → wraps → Vault Key (VK)  [AES-256-GCM keywrap]
//!                 → wraps → Item Key (IK) [AES-256-GCM keywrap]
//! ```

use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::Result;
use crate::primitives::{self, KEY_LEN, WRAPPED_KEY_LEN};

// ── Domain separation AAD tags ───────────────────────────────────────────────

const AAD_VAULT_KEY: &[u8] = b"pildora:v1:wrapped-vault-key";
const AAD_ITEM_KEY: &[u8] = b"pildora:v1:wrapped-item-key";
const AAD_RECOVERY_MEK: &[u8] = b"pildora:v1:recovery-wrapped-mek";

// HKDF info strings for sub-key derivation
const HKDF_INFO_AUTH: &[u8] = b"pildora:v1:auth-key";
const HKDF_INFO_MEK: &[u8] = b"pildora:v1:master-encryption-key";

// ── Key types ────────────────────────────────────────────────────────────────

/// Master Key — derived from the user's password via Argon2id.
/// Never stored; re-derived on unlock.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct MasterKey([u8; KEY_LEN]);

impl MasterKey {
    #[must_use]
    pub fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(bytes)
    }

    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for MasterKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("MasterKey([REDACTED])")
    }
}

/// Authentication Key — derived from MK via HKDF. Used for SRP-6a.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct AuthKey([u8; KEY_LEN]);

impl AuthKey {
    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for AuthKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AuthKey([REDACTED])")
    }
}

/// Master Encryption Key — derived from MK via HKDF. Wraps vault keys.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct MasterEncryptionKey([u8; KEY_LEN]);

impl MasterEncryptionKey {
    #[must_use]
    pub fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(bytes)
    }

    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for MasterEncryptionKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("MasterEncryptionKey([REDACTED])")
    }
}

/// Vault Key — random 256-bit key that encrypts items within a vault.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct VaultKey([u8; KEY_LEN]);

impl VaultKey {
    #[must_use]
    pub fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(bytes)
    }

    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for VaultKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("VaultKey([REDACTED])")
    }
}

/// Item Key — random 256-bit key that encrypts a single vault item.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct ItemKey([u8; KEY_LEN]);

impl ItemKey {
    #[must_use]
    pub fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(bytes)
    }

    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for ItemKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ItemKey([REDACTED])")
    }
}

/// A vault key wrapped (encrypted) by the MEK.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct WrappedVaultKey(pub Vec<u8>);

impl WrappedVaultKey {
    /// Expected length in bytes.
    pub const LEN: usize = WRAPPED_KEY_LEN;
}

/// An item key wrapped (encrypted) by a vault key.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct WrappedItemKey(pub Vec<u8>);

impl WrappedItemKey {
    /// Expected length in bytes.
    pub const LEN: usize = WRAPPED_KEY_LEN;
}

/// A recovery key — random secret that can unwrap the MEK as an alternate
/// path to account recovery. Encoded as human-readable grouped text.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct RecoveryKey([u8; KEY_LEN]);

impl RecoveryKey {
    /// Creates a recovery key from raw bytes.
    #[must_use]
    pub fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(bytes)
    }

    /// Raw bytes of the recovery key.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }

    /// Encode as a human-readable string in groups of 5 characters using
    /// Crockford Base32 (case-insensitive, no ambiguous chars).
    ///
    /// Format: `XXXXX-XXXXX-XXXXX-...-CC` where CC is a 2-char checksum.
    #[must_use]
    pub fn to_display_string(&self) -> String {
        // Simple base32 encoding using Crockford alphabet (no I, L, O, U)
        const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

        // Encode 32 bytes = 256 bits → ceil(256/5) = 52 base32 chars
        let mut chars = Vec::with_capacity(56);
        let mut buffer: u64 = 0;
        let mut bits_in_buffer = 0;

        for &byte in &self.0 {
            buffer = (buffer << 8) | u64::from(byte);
            bits_in_buffer += 8;
            while bits_in_buffer >= 5 {
                bits_in_buffer -= 5;
                let idx = ((buffer >> bits_in_buffer) & 0x1F) as usize;
                chars.push(ALPHABET[idx]);
            }
        }
        if bits_in_buffer > 0 {
            let idx = ((buffer << (5 - bits_in_buffer)) & 0x1F) as usize;
            chars.push(ALPHABET[idx]);
        }

        // 2-char checksum (first 10 bits of BLAKE2b hash)
        let hash = primitives::blake2b_hash(&self.0);
        let check_val = (u16::from(hash[0]) << 2) | (u16::from(hash[1]) >> 6);
        let c1 = ALPHABET[(check_val >> 5) as usize & 0x1F];
        let c2 = ALPHABET[(check_val & 0x1F) as usize];
        chars.push(c1);
        chars.push(c2);

        // Group in 5s separated by dashes
        let grouped: Vec<String> = chars
            .chunks(5)
            .map(|c| c.iter().map(|&b| b as char).collect())
            .collect();
        grouped.join("-")
    }
}

impl std::fmt::Debug for RecoveryKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("RecoveryKey([REDACTED])")
    }
}

/// MEK wrapped by the recovery key (stored alongside the vault).
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct RecoveryWrappedMek(pub Vec<u8>);

// ── Key derivation ───────────────────────────────────────────────────────────

/// Derive the master key from a password and salt using Argon2id.
pub fn derive_master_key(password: &[u8], salt: &[u8]) -> Result<MasterKey> {
    let bytes = primitives::derive_key_argon2id(password, salt)?;
    Ok(MasterKey(bytes))
}

/// Derive authentication key and master encryption key from the master key.
pub fn derive_sub_keys(mk: &MasterKey) -> Result<(AuthKey, MasterEncryptionKey)> {
    let auth_bytes = primitives::hkdf_sha256(mk.as_bytes(), None, HKDF_INFO_AUTH, KEY_LEN)?;
    let mek_bytes = primitives::hkdf_sha256(mk.as_bytes(), None, HKDF_INFO_MEK, KEY_LEN)?;

    let mut auth_arr = [0u8; KEY_LEN];
    auth_arr.copy_from_slice(&auth_bytes);

    let mut mek_arr = [0u8; KEY_LEN];
    mek_arr.copy_from_slice(&mek_bytes);

    Ok((AuthKey(auth_arr), MasterEncryptionKey(mek_arr)))
}

// ── Vault key operations ─────────────────────────────────────────────────────

/// Generate a random vault key.
#[must_use]
pub fn generate_vault_key() -> VaultKey {
    VaultKey(primitives::generate_random_key())
}

/// Wrap a vault key with the MEK for storage.
pub fn wrap_vault_key(vk: &VaultKey, mek: &MasterEncryptionKey) -> Result<WrappedVaultKey> {
    let wrapped = primitives::aes256_gcm_keywrap(mek.as_bytes(), vk.as_bytes(), AAD_VAULT_KEY)?;
    Ok(WrappedVaultKey(wrapped))
}

/// Unwrap a vault key using the MEK.
pub fn unwrap_vault_key(wrapped: &WrappedVaultKey, mek: &MasterEncryptionKey) -> Result<VaultKey> {
    let bytes = primitives::aes256_gcm_key_unwrap(mek.as_bytes(), &wrapped.0, AAD_VAULT_KEY)?;
    Ok(VaultKey(bytes))
}

// ── Item key operations ──────────────────────────────────────────────────────

/// Generate a random item key.
#[must_use]
pub fn generate_item_key() -> ItemKey {
    ItemKey(primitives::generate_random_key())
}

/// Wrap an item key with a vault key for storage.
pub fn wrap_item_key(ik: &ItemKey, vk: &VaultKey) -> Result<WrappedItemKey> {
    let wrapped = primitives::aes256_gcm_keywrap(vk.as_bytes(), ik.as_bytes(), AAD_ITEM_KEY)?;
    Ok(WrappedItemKey(wrapped))
}

/// Unwrap an item key using a vault key.
pub fn unwrap_item_key(wrapped: &WrappedItemKey, vk: &VaultKey) -> Result<ItemKey> {
    let bytes = primitives::aes256_gcm_key_unwrap(vk.as_bytes(), &wrapped.0, AAD_ITEM_KEY)?;
    Ok(ItemKey(bytes))
}

// ── Vault rekey ──────────────────────────────────────────────────────────────

/// Re-wrap all item keys from an old vault key to a new one.
///
/// This is a **re-wrap** operation: each item key is unwrapped with `old_vk`
/// and re-wrapped with `new_vk`. Item ciphertext is not touched.
pub fn vault_rekey(
    old_vk: &VaultKey,
    new_vk: &VaultKey,
    wrapped_item_keys: &[WrappedItemKey],
) -> Result<Vec<WrappedItemKey>> {
    wrapped_item_keys
        .iter()
        .map(|wik| {
            let ik = unwrap_item_key(wik, old_vk)?;
            wrap_item_key(&ik, new_vk)
        })
        .collect()
}

// ── Recovery key ─────────────────────────────────────────────────────────────

/// Generate a random recovery key.
#[must_use]
pub fn generate_recovery_key() -> RecoveryKey {
    RecoveryKey(primitives::generate_random_key())
}

/// Wrap the MEK with the recovery key for offline backup.
pub fn wrap_mek_for_recovery(
    mek: &MasterEncryptionKey,
    recovery_key: &RecoveryKey,
) -> Result<RecoveryWrappedMek> {
    let wrapped =
        primitives::aes256_gcm_keywrap(recovery_key.as_bytes(), mek.as_bytes(), AAD_RECOVERY_MEK)?;
    Ok(RecoveryWrappedMek(wrapped))
}

/// Unwrap the MEK using a recovery key.
pub fn unwrap_mek_from_recovery(
    wrapped: &RecoveryWrappedMek,
    recovery_key: &RecoveryKey,
) -> Result<MasterEncryptionKey> {
    let bytes =
        primitives::aes256_gcm_key_unwrap(recovery_key.as_bytes(), &wrapped.0, AAD_RECOVERY_MEK)?;
    Ok(MasterEncryptionKey(bytes))
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_PASSWORD: &[u8] = b"correct horse battery staple";
    const TEST_SALT: &[u8] = b"saltsaltsaltsalt"; // 16 bytes

    // ── Master key derivation ────────────────────────────────────────────

    #[test]
    fn derive_master_key_deterministic() {
        let mk1 = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let mk2 = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        assert_eq!(mk1.as_bytes(), mk2.as_bytes());
    }

    #[test]
    fn derive_master_key_different_passwords() {
        let mk1 = derive_master_key(b"password1", TEST_SALT).unwrap();
        let mk2 = derive_master_key(b"password2", TEST_SALT).unwrap();
        assert_ne!(mk1.as_bytes(), mk2.as_bytes());
    }

    // ── Sub-key derivation ───────────────────────────────────────────────

    #[test]
    fn derive_sub_keys_produces_different_keys() {
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (auth, mek) = derive_sub_keys(&mk).unwrap();
        assert_ne!(auth.as_bytes(), mek.as_bytes());
    }

    #[test]
    fn derive_sub_keys_deterministic() {
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (auth1, mek1) = derive_sub_keys(&mk).unwrap();
        let (auth2, mek2) = derive_sub_keys(&mk).unwrap();
        assert_eq!(auth1.as_bytes(), auth2.as_bytes());
        assert_eq!(mek1.as_bytes(), mek2.as_bytes());
    }

    // ── Full key hierarchy roundtrip ─────────────────────────────────────

    #[test]
    fn full_hierarchy_roundtrip() {
        // password → MK → MEK → wrap VK → unwrap VK → wrap IK → unwrap IK
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (_auth, mek) = derive_sub_keys(&mk).unwrap();

        let vk = generate_vault_key();
        let wrapped_vk = wrap_vault_key(&vk, &mek).unwrap();
        let unwrapped_vk = unwrap_vault_key(&wrapped_vk, &mek).unwrap();
        assert_eq!(vk.as_bytes(), unwrapped_vk.as_bytes());

        let ik = generate_item_key();
        let wrapped_ik = wrap_item_key(&ik, &unwrapped_vk).unwrap();
        let unwrapped_ik = unwrap_item_key(&wrapped_ik, &unwrapped_vk).unwrap();
        assert_eq!(ik.as_bytes(), unwrapped_ik.as_bytes());
    }

    // ── Wrong password fails to unwrap ───────────────────────────────────

    #[test]
    fn wrong_password_fails_to_unwrap_vault_key() {
        let mk_correct = derive_master_key(b"correct", TEST_SALT).unwrap();
        let (_, mek_correct) = derive_sub_keys(&mk_correct).unwrap();

        let vk = generate_vault_key();
        let wrapped_vk = wrap_vault_key(&vk, &mek_correct).unwrap();

        let mk_wrong = derive_master_key(b"wrong", TEST_SALT).unwrap();
        let (_, mek_wrong) = derive_sub_keys(&mk_wrong).unwrap();

        assert!(unwrap_vault_key(&wrapped_vk, &mek_wrong).is_err());
    }

    // ── Vault rekey ──────────────────────────────────────────────────────

    #[test]
    fn vault_rekey_rewraps_all_items() {
        let old_vk = generate_vault_key();
        let new_vk = generate_vault_key();

        // Create some item keys and wrap them with old VK
        let item_keys: Vec<ItemKey> = (0..5).map(|_| generate_item_key()).collect();
        let wrapped: Vec<WrappedItemKey> = item_keys
            .iter()
            .map(|ik| wrap_item_key(ik, &old_vk).unwrap())
            .collect();

        // Rekey
        let re_wrapped = vault_rekey(&old_vk, &new_vk, &wrapped).unwrap();
        assert_eq!(re_wrapped.len(), 5);

        // All items unwrappable with new VK
        for (i, wik) in re_wrapped.iter().enumerate() {
            let unwrapped = unwrap_item_key(wik, &new_vk).unwrap();
            assert_eq!(unwrapped.as_bytes(), item_keys[i].as_bytes());
        }

        // Old VK cannot unwrap re-wrapped keys
        for wik in &re_wrapped {
            assert!(unwrap_item_key(wik, &old_vk).is_err());
        }
    }

    #[test]
    fn vault_rekey_empty_list() {
        let old_vk = generate_vault_key();
        let new_vk = generate_vault_key();
        let result = vault_rekey(&old_vk, &new_vk, &[]).unwrap();
        assert!(result.is_empty());
    }

    // ── Recovery key ─────────────────────────────────────────────────────

    #[test]
    fn recovery_key_roundtrip() {
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (_, mek) = derive_sub_keys(&mk).unwrap();

        let rk = generate_recovery_key();
        let wrapped = wrap_mek_for_recovery(&mek, &rk).unwrap();
        let recovered_mek = unwrap_mek_from_recovery(&wrapped, &rk).unwrap();

        assert_eq!(mek.as_bytes(), recovered_mek.as_bytes());
    }

    #[test]
    fn recovery_key_wrong_key_fails() {
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (_, mek) = derive_sub_keys(&mk).unwrap();

        let rk = generate_recovery_key();
        let wrong_rk = generate_recovery_key();
        let wrapped = wrap_mek_for_recovery(&mek, &rk).unwrap();

        assert!(unwrap_mek_from_recovery(&wrapped, &wrong_rk).is_err());
    }

    #[test]
    fn recovery_key_can_unwrap_vault_keys() {
        // Full flow: recovery key → MEK → unwrap VK → unwrap IK
        let mk = derive_master_key(TEST_PASSWORD, TEST_SALT).unwrap();
        let (_, mek) = derive_sub_keys(&mk).unwrap();

        let vk = generate_vault_key();
        let wrapped_vk = wrap_vault_key(&vk, &mek).unwrap();

        let ik = generate_item_key();
        let wrapped_ik = wrap_item_key(&ik, &vk).unwrap();

        // Simulate recovery
        let rk = generate_recovery_key();
        let recovery_blob = wrap_mek_for_recovery(&mek, &rk).unwrap();

        let recovered_mek = unwrap_mek_from_recovery(&recovery_blob, &rk).unwrap();
        let recovered_vk = unwrap_vault_key(&wrapped_vk, &recovered_mek).unwrap();
        let recovered_ik = unwrap_item_key(&wrapped_ik, &recovered_vk).unwrap();

        assert_eq!(ik.as_bytes(), recovered_ik.as_bytes());
    }

    #[test]
    fn recovery_key_display_format() {
        let rk = generate_recovery_key();
        let display = rk.to_display_string();
        // Should be groups of 5 separated by dashes, with checksum
        assert!(display.contains('-'));
        for group in display.split('-') {
            assert!(group.len() <= 5);
            assert!(group.chars().all(|c| c.is_ascii_alphanumeric()));
        }
    }

    #[test]
    fn recovery_key_display_deterministic() {
        let bytes = [0x42u8; KEY_LEN];
        let rk = RecoveryKey(bytes);
        let d1 = rk.to_display_string();
        let rk2 = RecoveryKey(bytes);
        let d2 = rk2.to_display_string();
        assert_eq!(d1, d2);
    }

    // ── Debug redaction ──────────────────────────────────────────────────

    #[test]
    fn all_key_types_redacted() {
        let mk = MasterKey::from_bytes([0; KEY_LEN]);
        let ak = AuthKey([0; KEY_LEN]);
        let mek = MasterEncryptionKey::from_bytes([0; KEY_LEN]);
        let vk = VaultKey::from_bytes([0; KEY_LEN]);
        let ik = ItemKey::from_bytes([0; KEY_LEN]);
        let rk = RecoveryKey([0; KEY_LEN]);

        assert!(format!("{mk:?}").contains("REDACTED"));
        assert!(format!("{ak:?}").contains("REDACTED"));
        assert!(format!("{mek:?}").contains("REDACTED"));
        assert!(format!("{vk:?}").contains("REDACTED"));
        assert!(format!("{ik:?}").contains("REDACTED"));
        assert!(format!("{rk:?}").contains("REDACTED"));
    }

    // ── Domain separation ────────────────────────────────────────────────

    #[test]
    fn vault_key_and_item_key_wrapping_not_interchangeable() {
        // A vault key wrapped with MEK should not be unwrappable as an item key
        // (and vice versa) due to AAD domain separation.
        let mek = MasterEncryptionKey::from_bytes(primitives::generate_random_key());
        let vk = generate_vault_key();

        let wrapped_vk = wrap_vault_key(&vk, &mek).unwrap();

        // Try to unwrap it as if it were an item key (using mek as vk)
        let fake_vk = VaultKey::from_bytes(*mek.as_bytes());
        let fake_wik = WrappedItemKey(wrapped_vk.0.clone());
        assert!(unwrap_item_key(&fake_wik, &fake_vk).is_err());
    }
}
