//! Vault operations — key generation, wrapping, and item encryption.
//!
//! Each vault has its own symmetric key (VK). Each item within a vault has
//! its own item key (IK), wrapped by the VK. This module will provide the
//! high-level API for vault lifecycle operations.
//!
//! Implementation is tracked in issues #7 and #8.

// Vault operations will be implemented in issue #7 (key hierarchy) and
// issue #8 (item encryption). This module is a placeholder that ensures
// the crate structure compiles.

/// Placeholder for vault identifier type.
pub type VaultId = uuid::Uuid;
