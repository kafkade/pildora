//! Session management — caches MEK for session persistence.
//!
//! Uses a file-based session store at `<data_dir>/.session`. The MEK is
//! hex-encoded and written to disk so that subsequent CLI invocations can
//! operate on the unlocked vault without re-prompting for the password.
//!
//! **Security note:** a file-based session is less secure than an OS keyring.
//! On supported platforms this should be replaced with keyring integration
//! (e.g. macOS Keychain, Windows Credential Manager) in a future release.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum SessionError {
    #[error("session I/O error: {0}")]
    Io(#[from] io::Error),
    #[error("invalid session data")]
    Invalid,
}

/// File-based session manager.
pub struct Session {
    session_path: PathBuf,
}

impl Session {
    /// Create a new session manager rooted at the given data directory.
    pub fn new(data_dir: &Path) -> Self {
        Self {
            session_path: data_dir.join(".session"),
        }
    }

    /// Store MEK bytes (hex-encoded) in the session file.
    pub fn store_mek(&self, mek_bytes: &[u8]) -> Result<(), SessionError> {
        let encoded = hex::encode(mek_bytes);
        fs::write(&self.session_path, encoded)?;
        Ok(())
    }

    /// Load MEK bytes from the session file. Returns `None` if no session.
    pub fn load_mek(&self) -> Result<Option<Vec<u8>>, SessionError> {
        if !self.session_path.exists() {
            return Ok(None);
        }
        let encoded = fs::read_to_string(&self.session_path)?;
        let bytes = hex::decode(encoded.trim()).map_err(|_| SessionError::Invalid)?;
        Ok(Some(bytes))
    }

    /// Clear the session (delete the session file).
    pub fn clear(&self) -> Result<(), SessionError> {
        if self.session_path.exists() {
            fs::remove_file(&self.session_path)?;
        }
        Ok(())
    }

    /// Check if a session is active (session file exists and is non-empty).
    pub fn is_active(&self) -> bool {
        self.session_path.exists()
            && fs::metadata(&self.session_path)
                .map(|m| m.len() > 0)
                .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_store_load_clear() {
        let dir = tempfile::tempdir().unwrap();
        let session = Session::new(dir.path());

        assert!(!session.is_active());
        assert!(session.load_mek().unwrap().is_none());

        let mek = [0xABu8; 32];
        session.store_mek(&mek).unwrap();
        assert!(session.is_active());

        let loaded = session.load_mek().unwrap().unwrap();
        assert_eq!(loaded, mek);

        session.clear().unwrap();
        assert!(!session.is_active());
        assert!(session.load_mek().unwrap().is_none());
    }
}
