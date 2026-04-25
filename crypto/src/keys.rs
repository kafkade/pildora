//! Key types and sensitive wrappers.
//!
//! All key types in this module implement [`zeroize::Zeroize`] so that key
//! material is securely erased from memory when the value is dropped.

use zeroize::{Zeroize, ZeroizeOnDrop};

/// A 256-bit symmetric key used for AES-256-GCM encryption.
///
/// This is the base type for vault keys, item keys, and the master encryption
/// key. The inner bytes are zeroized on drop.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SymmetricKey([u8; 32]);

impl SymmetricKey {
    /// The length of the key in bytes.
    pub const LEN: usize = 32;

    /// Creates a key from raw bytes.
    ///
    /// # Panics
    ///
    /// Does not panic — the array size is enforced by the type system.
    #[must_use]
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns a reference to the raw key bytes.
    ///
    /// Callers must not persist or log this data.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Debug for SymmetricKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SymmetricKey([REDACTED])")
    }
}

/// A salt used for key derivation (Argon2id).
///
/// Stored alongside the encrypted vault metadata so the correct salt is
/// available during unlock.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct Salt(pub Vec<u8>);

impl Salt {
    /// The recommended salt length in bytes (128-bit).
    pub const RECOMMENDED_LEN: usize = 16;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symmetric_key_debug_redacted() {
        let key = SymmetricKey::from_bytes([0xAB; 32]);
        let debug = format!("{key:?}");
        assert_eq!(debug, "SymmetricKey([REDACTED])");
        assert!(!debug.contains("AB"));
    }

    #[test]
    fn symmetric_key_roundtrip() {
        let bytes = [42u8; 32];
        let key = SymmetricKey::from_bytes(bytes);
        assert_eq!(key.as_bytes(), &bytes);
    }
}
