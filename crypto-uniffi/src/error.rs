//! FFI-safe error type for the `UniFFI` bridge.
//!
//! This type flattens [`pildora_crypto::error::CryptoError`] into a shape that
//! `UniFFI` can represent across the FFI boundary. Each variant carries a
//! human-readable `message` string — structured error data stays on the Rust
//! side; Swift receives a typed enum with display text.

use pildora_crypto::error::CryptoError;

/// Errors returned by FFI-exported functions.
///
/// Mapped from [`CryptoError`] with [`From`]; all detail is captured in
/// `message` so the Rust error chain is not exposed across FFI.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum FfiError {
    /// A function received an argument with an invalid size or format.
    #[error("invalid argument: {message}")]
    InvalidArgument { message: String },

    /// Key derivation failed (Argon2id, HKDF).
    #[error("key derivation failed: {message}")]
    KeyDerivation { message: String },

    /// Encryption failed.
    #[error("encryption failed: {message}")]
    Encryption { message: String },

    /// Decryption failed — wrong key, corrupted data, or tampered ciphertext.
    #[error("decryption failed: {message}")]
    Decryption { message: String },

    /// Key wrapping or unwrapping failed.
    #[error("key wrap/unwrap failed: {message}")]
    KeyWrap { message: String },

    /// Serialization or deserialization failed.
    #[error("serialization error: {message}")]
    Serialization { message: String },

    /// An SRP-6a authentication step failed.
    #[error("authentication error: {message}")]
    Authentication { message: String },
}

impl From<CryptoError> for FfiError {
    fn from(err: CryptoError) -> Self {
        match err {
            CryptoError::KeyDerivation(msg) => Self::KeyDerivation { message: msg },
            CryptoError::Encryption(msg) => Self::Encryption { message: msg },
            CryptoError::Decryption(msg) => Self::Decryption { message: msg },
            CryptoError::KeyWrap(msg) => Self::KeyWrap { message: msg },
            CryptoError::UnsupportedBlobVersion { version } => Self::Decryption {
                message: format!("unsupported blob version: {version}"),
            },
            CryptoError::Serialization(msg) => Self::Serialization { message: msg },
            CryptoError::Srp(msg) => Self::Authentication { message: msg },
        }
    }
}
