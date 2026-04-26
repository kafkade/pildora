use pildora_crypto::key_hierarchy;
use pildora_crypto::vault::{EncryptedBlob, encrypt_json, item_encrypt};

// The `storage` module is private to the binary crate, so integration tests
// exercise it through a re-exported path or by recreating the types directly.
// Since the storage module lives in the binary crate, we use rusqlite directly
// and replicate the module for testing.  Instead we just use the lib-style
// approach: the storage module is compiled as part of the test binary via
// the include path trick.
//
// Actually, the simplest approach: we test the storage logic by importing
// the crate's internal modules. Since `pildora-cli` is a binary crate, we
// cannot do `use pildora_cli::storage`.  The standard Rust approach is to
// create a lib.rs that re-exports modules.  Let's write the tests against
// the raw SQLite storage using the same schema.

use std::path::Path;

/// A stripped-down re-implementation of Storage for integration testing.
/// This mirrors the CLI's Storage struct and schema exactly.
mod test_storage {
    use rusqlite::{Connection, params};
    use std::fs;
    use std::path::{Path, PathBuf};

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

    pub struct Storage {
        conn: Connection,
        _data_dir: PathBuf,
    }

    impl Storage {
        pub fn open(data_dir: &Path) -> Result<Self, Box<dyn std::error::Error>> {
            fs::create_dir_all(data_dir)?;
            let db_path = data_dir.join("pildora.db");
            let conn = Connection::open(&db_path)?;

            conn.pragma_update(None, "journal_mode", "WAL")?;
            conn.pragma_update(None, "busy_timeout", 5000)?;
            conn.pragma_update(None, "foreign_keys", "ON")?;

            conn.execute_batch(
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

            let count: i64 =
                conn.query_row("SELECT COUNT(*) FROM schema_version", [], |r| r.get(0))?;
            if count == 0 {
                conn.execute(
                    "INSERT INTO schema_version (version) VALUES (?1)",
                    params![1],
                )?;
            }

            Ok(Self {
                conn,
                _data_dir: data_dir.to_path_buf(),
            })
        }

        pub fn init_account(
            &self,
            salt: &[u8],
            recovery_wrapped_mek: &[u8],
            recovery_key_encrypted: &[u8],
        ) -> Result<(), Box<dyn std::error::Error>> {
            let initialized: i64 = self.conn.query_row(
                "SELECT COUNT(*) FROM account_state WHERE id = 1",
                [],
                |r| r.get(0),
            )?;
            if initialized > 0 {
                return Err("already initialized".into());
            }

            let now = chrono::Utc::now().to_rfc3339();
            self.conn.execute(
                "INSERT INTO account_state (id, salt, recovery_wrapped_mek, recovery_key_encrypted, created_at)
                 VALUES (1, ?1, ?2, ?3, ?4)",
                params![salt, recovery_wrapped_mek, recovery_key_encrypted, now],
            )?;
            Ok(())
        }

        pub fn load_account(&self) -> Result<Option<AccountState>, Box<dyn std::error::Error>> {
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

        pub fn is_initialized(&self) -> Result<bool, Box<dyn std::error::Error>> {
            let count: i64 = self.conn.query_row(
                "SELECT COUNT(*) FROM account_state WHERE id = 1",
                [],
                |r| r.get(0),
            )?;
            Ok(count > 0)
        }

        pub fn create_vault(
            &self,
            id: &str,
            encrypted_metadata: &[u8],
            wrapped_vk: &[u8],
        ) -> Result<(), Box<dyn std::error::Error>> {
            let now = chrono::Utc::now().to_rfc3339();
            self.conn.execute(
                "INSERT INTO vaults (id, encrypted_metadata, wrapped_vault_key, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![id, encrypted_metadata, wrapped_vk, now, now],
            )?;
            Ok(())
        }

        pub fn list_vault_ids(&self) -> Result<Vec<String>, Box<dyn std::error::Error>> {
            let mut stmt = self
                .conn
                .prepare("SELECT id FROM vaults ORDER BY created_at")?;
            let ids = stmt
                .query_map([], |row| row.get(0))?
                .collect::<Result<Vec<String>, _>>()?;
            Ok(ids)
        }

        pub fn get_wrapped_vault_key(
            &self,
            vault_id: &str,
        ) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
            let key = self.conn.query_row(
                "SELECT wrapped_vault_key FROM vaults WHERE id = ?1",
                params![vault_id],
                |row| row.get(0),
            )?;
            Ok(key)
        }

        pub fn get_vault_metadata(
            &self,
            vault_id: &str,
        ) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
            let meta = self.conn.query_row(
                "SELECT encrypted_metadata FROM vaults WHERE id = ?1",
                params![vault_id],
                |row| row.get(0),
            )?;
            Ok(meta)
        }

        pub fn store_item(
            &self,
            id: &str,
            vault_id: &str,
            item_type: &str,
            blob: &[u8],
        ) -> Result<(), Box<dyn std::error::Error>> {
            let now = chrono::Utc::now().to_rfc3339();
            self.conn.execute(
                "INSERT INTO encrypted_items (id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6)",
                params![id, vault_id, item_type, blob, now, now],
            )?;
            Ok(())
        }

        pub fn load_item(&self, id: &str) -> Result<ItemRow, Box<dyn std::error::Error>> {
            let row = self.conn.query_row(
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
            )?;
            Ok(row)
        }

        pub fn list_item_rows(
            &self,
            vault_id: &str,
            item_type: Option<&str>,
        ) -> Result<Vec<ItemRow>, Box<dyn std::error::Error>> {
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

        pub fn delete_item(&self, id: &str) -> Result<bool, Box<dyn std::error::Error>> {
            let deleted = self
                .conn
                .execute("DELETE FROM encrypted_items WHERE id = ?1", params![id])?;
            Ok(deleted > 0)
        }

        pub fn update_item(
            &self,
            id: &str,
            blob: &[u8],
        ) -> Result<bool, Box<dyn std::error::Error>> {
            let now = chrono::Utc::now().to_rfc3339();
            let updated = self.conn.execute(
                "UPDATE encrypted_items SET encrypted_blob = ?1, updated_at = ?2 WHERE id = ?3",
                params![blob, now, id],
            )?;
            Ok(updated > 0)
        }

        pub fn count_items(
            &self,
            vault_id: &str,
            item_type: Option<&str>,
        ) -> Result<usize, Box<dyn std::error::Error>> {
            let count: i64 = if let Some(itype) = item_type {
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
}

use test_storage::Storage;

fn open_temp_storage(dir: &Path) -> Storage {
    Storage::open(dir).expect("failed to open storage")
}

// ── 1. Schema creation ──────────────────────────────────────────────────────

#[test]
fn schema_tables_exist() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    // Verify tables exist by querying sqlite_master
    let conn = rusqlite::Connection::open(tmp.path().join("pildora.db")).unwrap();
    let tables: Vec<String> = {
        let mut stmt = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .unwrap();
        stmt.query_map([], |row| row.get(0))
            .unwrap()
            .collect::<Result<Vec<String>, _>>()
            .unwrap()
    };

    assert!(tables.contains(&"account_state".to_string()));
    assert!(tables.contains(&"vaults".to_string()));
    assert!(tables.contains(&"encrypted_items".to_string()));
    assert!(tables.contains(&"schema_version".to_string()));

    // Schema version should be 1
    let version: i64 = conn
        .query_row("SELECT version FROM schema_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, 1);

    drop(storage);
}

// ── 2. Account state roundtrip ──────────────────────────────────────────────

#[test]
fn account_state_roundtrip() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let salt = b"sixteen_byte_sal";
    let recovery_mek = b"wrapped_mek_data_here";
    let recovery_enc = b"encrypted_recovery_key";

    storage
        .init_account(salt, recovery_mek, recovery_enc)
        .unwrap();

    let account = storage
        .load_account()
        .unwrap()
        .expect("account should exist");
    assert_eq!(account.salt, salt.to_vec());
    assert_eq!(account.argon2_memory_kib, 65536);
    assert_eq!(account.argon2_iterations, 3);
    assert_eq!(account.argon2_parallelism, 1);
    assert_eq!(
        account.recovery_wrapped_mek.as_deref(),
        Some(recovery_mek.as_slice())
    );
    assert_eq!(
        account.recovery_key_encrypted.as_deref(),
        Some(recovery_enc.as_slice())
    );
    assert!(!account.created_at.is_empty());
}

// ── 3. Vault creation ───────────────────────────────────────────────────────

#[test]
fn vault_create_and_list() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let vault_id = uuid::Uuid::new_v4().to_string();
    let meta = b"encrypted_metadata_blob";
    let wrapped_vk = b"wrapped_vault_key_60_bytes_placeholder_data_here_pad1234567";

    storage.create_vault(&vault_id, meta, wrapped_vk).unwrap();

    let ids = storage.list_vault_ids().unwrap();
    assert_eq!(ids.len(), 1);
    assert_eq!(ids[0], vault_id);

    let loaded_vk = storage.get_wrapped_vault_key(&vault_id).unwrap();
    assert_eq!(loaded_vk, wrapped_vk.to_vec());

    let loaded_meta = storage.get_vault_metadata(&vault_id).unwrap();
    assert_eq!(loaded_meta, meta.to_vec());
}

// ── 4. Item CRUD ────────────────────────────────────────────────────────────

#[test]
fn item_crud() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let vault_id = uuid::Uuid::new_v4().to_string();
    storage
        .create_vault(
            &vault_id,
            b"meta",
            b"wrapped_key_placeholder_60bytes_padding_here_1234567890",
        )
        .unwrap();

    let item_id = uuid::Uuid::new_v4().to_string();
    let blob = b"encrypted_item_data";

    // Store
    storage
        .store_item(&item_id, &vault_id, "medication", blob)
        .unwrap();

    // Load
    let row = storage.load_item(&item_id).unwrap();
    assert_eq!(row.id, item_id);
    assert_eq!(row.vault_id, vault_id);
    assert_eq!(row.item_type, "medication");
    assert_eq!(row.encrypted_blob, blob.to_vec());
    assert_eq!(row.blob_version, 1);

    // Update
    let new_blob = b"updated_encrypted_data";
    let updated = storage.update_item(&item_id, new_blob).unwrap();
    assert!(updated);

    let row = storage.load_item(&item_id).unwrap();
    assert_eq!(row.encrypted_blob, new_blob.to_vec());

    // Delete
    let deleted = storage.delete_item(&item_id).unwrap();
    assert!(deleted);

    // Load after delete should fail
    let result = storage.load_item(&item_id);
    assert!(result.is_err());
}

// ── 5. Typed roundtrip (encrypt → store → load → decrypt) ──────────────────

#[test]
fn typed_roundtrip() {
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct Medication {
        name: String,
        dosage: Option<String>,
        form: Option<String>,
        notes: Option<String>,
    }

    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    // Create vault with real crypto
    let vk = key_hierarchy::generate_vault_key();
    let vault_id = uuid::Uuid::new_v4().to_string();
    storage
        .create_vault(
            &vault_id,
            b"meta",
            b"wrapped_key_placeholder_60bytes_padding_here_1234567890",
        )
        .unwrap();

    let med = Medication {
        name: "Aspirin".into(),
        dosage: Some("100mg".into()),
        form: Some("tablet".into()),
        notes: Some("Take with food".into()),
    };

    // Encrypt and store
    let blob = encrypt_json(&med, &vk).unwrap();
    let item_id = uuid::Uuid::new_v4().to_string();
    storage
        .store_item(&item_id, &vault_id, "medication", blob.to_bytes())
        .unwrap();

    // Load and decrypt
    let row = storage.load_item(&item_id).unwrap();
    let loaded_blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
    let loaded: Medication = pildora_crypto::vault::decrypt_json(&loaded_blob, &vk).unwrap();

    assert_eq!(loaded, med);
}

// ── 6. Wrong vault key cannot decrypt ───────────────────────────────────────

#[test]
fn wrong_vault_key_fails() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let vk1 = key_hierarchy::generate_vault_key();
    let vk2 = key_hierarchy::generate_vault_key();
    let vault_id = uuid::Uuid::new_v4().to_string();
    storage
        .create_vault(
            &vault_id,
            b"meta",
            b"wrapped_key_placeholder_60bytes_padding_here_1234567890",
        )
        .unwrap();

    let plaintext = b"secret medication data";
    let blob = item_encrypt(plaintext, &vk1).unwrap();

    let item_id = uuid::Uuid::new_v4().to_string();
    storage
        .store_item(&item_id, &vault_id, "medication", blob.to_bytes())
        .unwrap();

    // Try to decrypt with wrong key
    let row = storage.load_item(&item_id).unwrap();
    let loaded_blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
    let result = pildora_crypto::vault::item_decrypt(&loaded_blob, &vk2);
    assert!(result.is_err(), "decryption with wrong key should fail");
}

// ── 7. Not initialized ─────────────────────────────────────────────────────

#[test]
fn not_initialized_returns_none() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    assert!(!storage.is_initialized().unwrap());
    assert!(storage.load_account().unwrap().is_none());
}

// ── 8. Count items ──────────────────────────────────────────────────────────

#[test]
fn count_items() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let vault_id = uuid::Uuid::new_v4().to_string();
    storage
        .create_vault(
            &vault_id,
            b"meta",
            b"wrapped_key_placeholder_60bytes_padding_here_1234567890",
        )
        .unwrap();

    // Store 3 medications and 2 schedules
    for i in 0..3 {
        let id = uuid::Uuid::new_v4().to_string();
        storage
            .store_item(&id, &vault_id, "medication", format!("blob_{i}").as_bytes())
            .unwrap();
    }
    for i in 0..2 {
        let id = uuid::Uuid::new_v4().to_string();
        storage
            .store_item(&id, &vault_id, "schedule", format!("sched_{i}").as_bytes())
            .unwrap();
    }

    assert_eq!(storage.count_items(&vault_id, None).unwrap(), 5);
    assert_eq!(
        storage.count_items(&vault_id, Some("medication")).unwrap(),
        3
    );
    assert_eq!(storage.count_items(&vault_id, Some("schedule")).unwrap(), 2);
    assert_eq!(storage.count_items(&vault_id, Some("dose_log")).unwrap(), 0);
}

// ── 9. Delete by ID ────────────────────────────────────────────────────────

#[test]
fn delete_item_by_id() {
    let tmp = tempfile::tempdir().unwrap();
    let storage = open_temp_storage(tmp.path());

    let vault_id = uuid::Uuid::new_v4().to_string();
    storage
        .create_vault(
            &vault_id,
            b"meta",
            b"wrapped_key_placeholder_60bytes_padding_here_1234567890",
        )
        .unwrap();

    let id1 = uuid::Uuid::new_v4().to_string();
    let id2 = uuid::Uuid::new_v4().to_string();
    storage
        .store_item(&id1, &vault_id, "medication", b"blob1")
        .unwrap();
    storage
        .store_item(&id2, &vault_id, "medication", b"blob2")
        .unwrap();

    assert_eq!(storage.count_items(&vault_id, None).unwrap(), 2);

    // Delete first item
    assert!(storage.delete_item(&id1).unwrap());
    assert_eq!(storage.count_items(&vault_id, None).unwrap(), 1);

    // Second item still exists
    let row = storage.load_item(&id2).unwrap();
    assert_eq!(row.id, id2);

    // Deleting nonexistent item returns false
    assert!(!storage.delete_item(&id1).unwrap());
}
