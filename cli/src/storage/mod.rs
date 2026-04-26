pub mod typed;

use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{Connection, params};
use thiserror::Error;

/// Current database schema version.
const SCHEMA_VERSION: i64 = 1;

// ── Error type ───────────────────────────────────────────────────────────────

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("not initialized — run `pildora init` first")]
    NotInitialized,
    #[error("already initialized")]
    AlreadyInitialized,
    #[error("item not found: {0}")]
    NotFound(String),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

// ── Supporting types ─────────────────────────────────────────────────────────

#[derive(Debug)]
pub struct AccountState {
    pub salt: Vec<u8>,
    pub argon2_memory_kib: u32,
    pub argon2_iterations: u32,
    pub argon2_parallelism: u32,
    pub recovery_wrapped_mek: Option<Vec<u8>>,
    pub recovery_key_encrypted: Option<Vec<u8>>,
    pub created_at: String,
}

#[derive(Debug)]
pub struct ItemRow {
    pub id: String,
    pub vault_id: String,
    pub item_type: String,
    pub encrypted_blob: Vec<u8>,
    pub blob_version: i32,
    pub created_at: String,
    pub updated_at: String,
}

// ── Data directory ───────────────────────────────────────────────────────────

/// Get the default data directory for Pildora.
/// - Linux: `$XDG_DATA_HOME/pildora` or `~/.local/share/pildora`
/// - macOS: `~/Library/Application Support/pildora`
/// - Windows: `%APPDATA%\pildora`
pub fn default_data_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("pildora")
}

// ── Storage ──────────────────────────────────────────────────────────────────

pub struct Storage {
    conn: Connection,
    data_dir: PathBuf,
}

impl Storage {
    /// Open (or create) the storage database at `data_dir/pildora.db`.
    pub fn open(data_dir: &Path) -> Result<Self, StorageError> {
        fs::create_dir_all(data_dir)?;

        let db_path = data_dir.join("pildora.db");
        let conn = Connection::open(&db_path)?;

        // Pragmas
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "busy_timeout", 5000)?;
        conn.pragma_update(None, "foreign_keys", "ON")?;

        let storage = Self {
            conn,
            data_dir: data_dir.to_path_buf(),
        };
        storage.run_migrations()?;

        Ok(storage)
    }

    /// Return the data directory this storage was opened with.
    pub fn data_dir(&self) -> &Path {
        &self.data_dir
    }

    // ── Migrations ───────────────────────────────────────────────────────

    fn run_migrations(&self) -> Result<(), StorageError> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_version (
                 version INTEGER NOT NULL
             );

             CREATE TABLE IF NOT EXISTS account_state (
                 id INTEGER PRIMARY KEY CHECK (id = 1),
                 salt BLOB NOT NULL,
                 argon2_memory_kib INTEGER NOT NULL DEFAULT 65536,
                 argon2_iterations INTEGER NOT NULL DEFAULT 3,
                 argon2_parallelism INTEGER NOT NULL DEFAULT 1,
                 recovery_wrapped_mek BLOB,
                 recovery_key_encrypted BLOB,
                 created_at TEXT NOT NULL
             );

             CREATE TABLE IF NOT EXISTS vaults (
                 id TEXT PRIMARY KEY,
                 encrypted_metadata BLOB NOT NULL,
                 wrapped_vault_key BLOB NOT NULL,
                 created_at TEXT NOT NULL,
                 updated_at TEXT NOT NULL
             );

             CREATE TABLE IF NOT EXISTS encrypted_items (
                 id TEXT PRIMARY KEY,
                 vault_id TEXT NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
                 item_type TEXT NOT NULL,
                 encrypted_blob BLOB NOT NULL,
                 blob_version INTEGER NOT NULL DEFAULT 1,
                 created_at TEXT NOT NULL,
                 updated_at TEXT NOT NULL
             );",
        )?;

        // Seed version if table is empty
        let count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM schema_version", [], |r| r.get(0))?;
        if count == 0 {
            self.conn.execute(
                "INSERT INTO schema_version (version) VALUES (?1)",
                params![SCHEMA_VERSION],
            )?;
        }

        Ok(())
    }

    // ── Account state ────────────────────────────────────────────────────

    /// Initialize account state (salt, argon2 params, recovery data).
    pub fn init_account(
        &self,
        salt: &[u8],
        recovery_wrapped_mek: &[u8],
        recovery_key_encrypted: &[u8],
    ) -> Result<(), StorageError> {
        if self.is_initialized()? {
            return Err(StorageError::AlreadyInitialized);
        }

        let now = chrono::Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO account_state (id, salt, recovery_wrapped_mek, recovery_key_encrypted, created_at)
             VALUES (1, ?1, ?2, ?3, ?4)",
            params![salt, recovery_wrapped_mek, recovery_key_encrypted, now],
        )?;

        Ok(())
    }

    /// Load account state.
    pub fn load_account(&self) -> Result<Option<AccountState>, StorageError> {
        let mut stmt = self.conn.prepare(
            "SELECT salt, argon2_memory_kib, argon2_iterations, argon2_parallelism,
                    recovery_wrapped_mek, recovery_key_encrypted, created_at
             FROM account_state WHERE id = 1",
        )?;

        let mut rows = stmt.query_map([], |row| {
            Ok(AccountState {
                salt: row.get(0)?,
                argon2_memory_kib: row.get(1)?,
                argon2_iterations: row.get(2)?,
                argon2_parallelism: row.get(3)?,
                recovery_wrapped_mek: row.get(4)?,
                recovery_key_encrypted: row.get(5)?,
                created_at: row.get(6)?,
            })
        })?;

        match rows.next() {
            Some(row) => Ok(Some(row?)),
            None => Ok(None),
        }
    }

    /// Check if the account has been initialized.
    pub fn is_initialized(&self) -> Result<bool, StorageError> {
        let count: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM account_state WHERE id = 1", [], |r| {
                    r.get(0)
                })?;
        Ok(count > 0)
    }

    /// Update recovery data (after regenerating the recovery key).
    pub fn update_recovery(
        &self,
        recovery_wrapped_mek: &[u8],
        recovery_key_encrypted: &[u8],
    ) -> Result<(), StorageError> {
        let updated = self.conn.execute(
            "UPDATE account_state SET recovery_wrapped_mek = ?1, recovery_key_encrypted = ?2 WHERE id = 1",
            params![recovery_wrapped_mek, recovery_key_encrypted],
        )?;
        if updated == 0 {
            return Err(StorageError::NotInitialized);
        }
        Ok(())
    }

    // ── Vaults ───────────────────────────────────────────────────────────

    /// Create a vault.
    pub fn create_vault(
        &self,
        id: &str,
        encrypted_metadata: &[u8],
        wrapped_vk: &[u8],
    ) -> Result<(), StorageError> {
        let now = chrono::Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO vaults (id, encrypted_metadata, wrapped_vault_key, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, encrypted_metadata, wrapped_vk, now, now],
        )?;
        Ok(())
    }

    /// List vault IDs.
    pub fn list_vault_ids(&self) -> Result<Vec<String>, StorageError> {
        let mut stmt = self
            .conn
            .prepare("SELECT id FROM vaults ORDER BY created_at")?;
        let ids = stmt
            .query_map([], |row| row.get(0))?
            .collect::<Result<Vec<String>, _>>()?;
        Ok(ids)
    }

    /// Get the wrapped vault key for a vault.
    pub fn get_wrapped_vault_key(&self, vault_id: &str) -> Result<Vec<u8>, StorageError> {
        self.conn
            .query_row(
                "SELECT wrapped_vault_key FROM vaults WHERE id = ?1",
                params![vault_id],
                |row| row.get(0),
            )
            .map_err(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => {
                    StorageError::NotFound(vault_id.to_string())
                }
                other => StorageError::Database(other),
            })
    }

    /// Get encrypted vault metadata.
    pub fn get_vault_metadata(&self, vault_id: &str) -> Result<Vec<u8>, StorageError> {
        self.conn
            .query_row(
                "SELECT encrypted_metadata FROM vaults WHERE id = ?1",
                params![vault_id],
                |row| row.get(0),
            )
            .map_err(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => {
                    StorageError::NotFound(vault_id.to_string())
                }
                other => StorageError::Database(other),
            })
    }

    // ── Encrypted items ──────────────────────────────────────────────────

    /// Store an encrypted item.
    pub fn store_item(
        &self,
        id: &str,
        vault_id: &str,
        item_type: &str,
        blob: &[u8],
    ) -> Result<(), StorageError> {
        let now = chrono::Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO encrypted_items (id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6)",
            params![id, vault_id, item_type, blob, now, now],
        )?;
        Ok(())
    }

    /// Load an encrypted item blob.
    pub fn load_item(&self, id: &str) -> Result<ItemRow, StorageError> {
        self.conn
            .query_row(
                "SELECT id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at
                 FROM encrypted_items WHERE id = ?1",
                params![id],
                |row| {
                    Ok(ItemRow {
                        id: row.get(0)?,
                        vault_id: row.get(1)?,
                        item_type: row.get(2)?,
                        encrypted_blob: row.get(3)?,
                        blob_version: row.get(4)?,
                        created_at: row.get(5)?,
                        updated_at: row.get(6)?,
                    })
                },
            )
            .map_err(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => StorageError::NotFound(id.to_string()),
                other => StorageError::Database(other),
            })
    }

    /// List item rows (without decrypting), optionally filtered by type.
    pub fn list_item_rows(
        &self,
        vault_id: &str,
        item_type: Option<&str>,
    ) -> Result<Vec<ItemRow>, StorageError> {
        let rows = if let Some(itype) = item_type {
            let mut stmt = self.conn.prepare(
                "SELECT id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at
                 FROM encrypted_items WHERE vault_id = ?1 AND item_type = ?2
                 ORDER BY created_at",
            )?;
            stmt.query_map(params![vault_id, itype], |row| {
                Ok(ItemRow {
                    id: row.get(0)?,
                    vault_id: row.get(1)?,
                    item_type: row.get(2)?,
                    encrypted_blob: row.get(3)?,
                    blob_version: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?
        } else {
            let mut stmt = self.conn.prepare(
                "SELECT id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at
                 FROM encrypted_items WHERE vault_id = ?1
                 ORDER BY created_at",
            )?;
            stmt.query_map(params![vault_id], |row| {
                Ok(ItemRow {
                    id: row.get(0)?,
                    vault_id: row.get(1)?,
                    item_type: row.get(2)?,
                    encrypted_blob: row.get(3)?,
                    blob_version: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?
        };
        Ok(rows)
    }

    /// Delete an item by ID. Returns `true` if a row was deleted.
    pub fn delete_item(&self, id: &str) -> Result<bool, StorageError> {
        let deleted = self
            .conn
            .execute("DELETE FROM encrypted_items WHERE id = ?1", params![id])?;
        Ok(deleted > 0)
    }

    /// Update an encrypted item blob. Returns `true` if a row was updated.
    pub fn update_item(&self, id: &str, blob: &[u8]) -> Result<bool, StorageError> {
        let now = chrono::Utc::now().to_rfc3339();
        let updated = self.conn.execute(
            "UPDATE encrypted_items SET encrypted_blob = ?1, updated_at = ?2 WHERE id = ?3",
            params![blob, now, id],
        )?;
        Ok(updated > 0)
    }

    /// Count items by type in a vault.
    pub fn count_items(
        &self,
        vault_id: &str,
        item_type: Option<&str>,
    ) -> Result<usize, StorageError> {
        let count: u32 = if let Some(itype) = item_type {
            self.conn.query_row(
                "SELECT COUNT(*) FROM encrypted_items WHERE vault_id = ?1 AND item_type = ?2",
                params![vault_id, itype],
                |r| r.get(0),
            )?
        } else {
            self.conn.query_row(
                "SELECT COUNT(*) FROM encrypted_items WHERE vault_id = ?1",
                params![vault_id],
                |r| r.get(0),
            )?
        };
        Ok(count as usize)
    }
}
