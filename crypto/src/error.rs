//! Error types for pildora-crypto operations.

use thiserror::Error;

/// Errors that can occur during cryptographic operations.
#[derive(Debug, Error)]
pub enum CryptoError {
    /// Key derivation failed (invalid parameters or resource exhaustion).
    #[error("key derivation failed: {0}")]
    KeyDerivation(String),

    /// Encryption failed.
    #[error("encryption failed: {0}")]
    Encryption(String),

    /// Decryption failed — wrong key, corrupted data, or tampered ciphertext.
    #[error("decryption failed: {0}")]
    Decryption(String),

    /// Key wrapping or unwrapping failed.
    #[error("key wrap/unwrap failed: {0}")]
    KeyWrap(String),

    /// The encrypted blob has an unrecognized version.
    #[error("unsupported blob version: {version}")]
    UnsupportedBlobVersion { version: u8 },

    /// Serialization or deserialization of a domain object failed.
    #[error("serialization error: {0}")]
    Serialization(String),
}

/// Convenience alias for results from crypto operations.
pub type Result<T> = std::result::Result<T, CryptoError>;
