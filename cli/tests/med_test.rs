use chrono::Utc;
use pildora_crypto::key_hierarchy;
use pildora_crypto::vault::{EncryptedBlob, decrypt_json, encrypt_json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Mirror types from the binary crate ──────────────────────────────────────
// Integration tests cannot import from a binary crate, so we replicate the
// Medication model and a thin Storage wrapper with the same schema.

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Medication {
    id: Uuid,
    name: String,
    generic_name: Option<String>,
    brand_name: Option<String>,
    dosage: String,
    form: String,
    prescriber: Option<String>,
    pharmacy: Option<String>,
    notes: Option<String>,
    rxnorm_id: Option<String>,
    start_date: Option<String>,
    end_date: Option<String>,
    created_at: chrono::DateTime<Utc>,
    updated_at: chrono::DateTime<Utc>,
}

const ITEM_TYPE: &str = "medication";

// ── Minimal test storage ────────────────────────────────────────────────────

mod test_storage {
    use rusqlite::{Connection, params};
    use std::fs;
    use std::path::{Path, PathBuf};

    #[derive(Debug)]
    pub struct ItemRow {
        pub id: String,
        pub encrypted_blob: Vec<u8>,
    }

    pub struct Storage {
        conn: Connection,
        _data_dir: PathBuf,
    }

    impl Storage {
        pub fn open(data_dir: &Path) -> Self {
            fs::create_dir_all(data_dir).unwrap();
            let db_path = data_dir.join("pildora.db");
            let conn = Connection::open(&db_path).unwrap();

            conn.pragma_update(None, "journal_mode", "WAL").unwrap();
            conn.pragma_update(None, "foreign_keys", "ON").unwrap();
            conn.execute_batch(
                "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);
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
            )
            .unwrap();

            Self {
                conn,
                _data_dir: data_dir.to_path_buf(),
            }
        }

        pub fn store_item(&self, id: &str, vault_id: &str, item_type: &str, blob: &[u8]) {
            let now = chrono::Utc::now().to_rfc3339();
            self.conn
                .execute(
                    "INSERT INTO encrypted_items \
                     (id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at) \
                     VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6)",
                    params![id, vault_id, item_type, blob, now, now],
                )
                .unwrap();
        }

        pub fn load_item(&self, id: &str) -> Option<ItemRow> {
            self.conn
                .query_row(
                    "SELECT id, encrypted_blob FROM encrypted_items WHERE id = ?1",
                    params![id],
                    |row| {
                        Ok(ItemRow {
                            id: row.get(0)?,
                            encrypted_blob: row.get(1)?,
                        })
                    },
                )
                .ok()
        }

        pub fn list_items(&self, vault_id: &str, item_type: &str) -> Vec<ItemRow> {
            let mut stmt = self
                .conn
                .prepare(
                    "SELECT id, encrypted_blob FROM encrypted_items \
                     WHERE vault_id = ?1 AND item_type = ?2 ORDER BY created_at",
                )
                .unwrap();
            stmt.query_map(params![vault_id, item_type], |row| {
                Ok(ItemRow {
                    id: row.get(0)?,
                    encrypted_blob: row.get(1)?,
                })
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
        }

        pub fn update_item(&self, id: &str, blob: &[u8]) -> bool {
            let now = chrono::Utc::now().to_rfc3339();
            let updated = self
                .conn
                .execute(
                    "UPDATE encrypted_items SET encrypted_blob = ?1, updated_at = ?2 WHERE id = ?3",
                    params![blob, now, id],
                )
                .unwrap();
            updated > 0
        }

        pub fn delete_item(&self, id: &str) -> bool {
            let deleted = self
                .conn
                .execute("DELETE FROM encrypted_items WHERE id = ?1", params![id])
                .unwrap();
            deleted > 0
        }

        pub fn count_items(&self, vault_id: &str, item_type: &str) -> usize {
            let count: i64 = self
                .conn
                .query_row(
                    "SELECT COUNT(*) FROM encrypted_items WHERE vault_id = ?1 AND item_type = ?2",
                    params![vault_id, item_type],
                    |r| r.get(0),
                )
                .unwrap();
            count as usize
        }

        pub fn create_vault(&self, id: &str) {
            let now = chrono::Utc::now().to_rfc3339();
            self.conn
                .execute(
                    "INSERT INTO vaults (id, encrypted_metadata, wrapped_vault_key, created_at, updated_at) \
                     VALUES (?1, X'00', X'00', ?2, ?3)",
                    params![id, now, now],
                )
                .unwrap();
        }
    }
}

use test_storage::Storage;

// ── Helpers ─────────────────────────────────────────────────────────────────

fn setup() -> (tempfile::TempDir, Storage, key_hierarchy::VaultKey, String) {
    let tmp = tempfile::tempdir().unwrap();
    let storage = Storage::open(tmp.path());
    let vault_id = Uuid::new_v4().to_string();
    storage.create_vault(&vault_id);
    let vk = key_hierarchy::generate_vault_key();
    (tmp, storage, vk, vault_id)
}

fn make_med(name: &str, dosage: &str, form: &str) -> Medication {
    let now = Utc::now();
    Medication {
        id: Uuid::new_v4(),
        name: name.to_string(),
        generic_name: None,
        brand_name: None,
        dosage: dosage.to_string(),
        form: form.to_string(),
        prescriber: None,
        pharmacy: None,
        notes: None,
        rxnorm_id: None,
        start_date: None,
        end_date: None,
        created_at: now,
        updated_at: now,
    }
}

fn store_med(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
    med: &Medication,
) -> String {
    let blob = encrypt_json(med, vk).unwrap();
    let item_id = Uuid::new_v4().to_string();
    storage.store_item(&item_id, vault_id, ITEM_TYPE, blob.to_bytes());
    item_id
}

fn load_med(storage: &Storage, vk: &key_hierarchy::VaultKey, item_id: &str) -> Medication {
    let row = storage.load_item(item_id).unwrap();
    let blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
    decrypt_json(&blob, vk).unwrap()
}

fn list_meds(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
) -> Vec<(String, Medication)> {
    storage
        .list_items(vault_id, ITEM_TYPE)
        .into_iter()
        .map(|row| {
            let blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
            let med: Medication = decrypt_json(&blob, vk).unwrap();
            (row.id, med)
        })
        .collect()
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[test]
fn add_medication() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med = make_med("Lisinopril", "10mg", "tablet");
    let item_id = store_med(&storage, &vk, &vault_id, &med);

    let loaded = load_med(&storage, &vk, &item_id);
    assert_eq!(loaded.name, "Lisinopril");
    assert_eq!(loaded.dosage, "10mg");
    assert_eq!(loaded.form, "tablet");
}

#[test]
fn list_medications() {
    let (_tmp, storage, vk, vault_id) = setup();

    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Lisinopril", "10mg", "tablet"),
    );
    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Vitamin D", "2000IU", "softgel"),
    );
    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Aspirin", "81mg", "tablet"),
    );

    let meds = list_meds(&storage, &vk, &vault_id);
    assert_eq!(meds.len(), 3);
}

#[test]
fn show_medication() {
    let (_tmp, storage, vk, vault_id) = setup();

    let mut med = make_med("Lisinopril", "10mg", "tablet");
    med.prescriber = Some("Dr. Smith".to_string());
    med.notes = Some("Take in morning".to_string());

    let item_id = store_med(&storage, &vk, &vault_id, &med);

    let loaded = load_med(&storage, &vk, &item_id);
    assert_eq!(loaded.name, "Lisinopril");
    assert_eq!(loaded.prescriber, Some("Dr. Smith".to_string()));
    assert_eq!(loaded.notes, Some("Take in morning".to_string()));
    assert_eq!(loaded.dosage, "10mg");
    assert_eq!(loaded.form, "tablet");
}

#[test]
fn edit_medication() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med = make_med("Lisinopril", "10mg", "tablet");
    let item_id = store_med(&storage, &vk, &vault_id, &med);

    // Edit dosage
    let mut loaded = load_med(&storage, &vk, &item_id);
    loaded.dosage = "20mg".to_string();
    loaded.updated_at = Utc::now();

    let blob = encrypt_json(&loaded, &vk).unwrap();
    assert!(storage.update_item(&item_id, blob.to_bytes()));

    let updated = load_med(&storage, &vk, &item_id);
    assert_eq!(updated.dosage, "20mg");
    assert_eq!(updated.name, "Lisinopril");
}

#[test]
fn delete_medication() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med = make_med("Lisinopril", "10mg", "tablet");
    let item_id = store_med(&storage, &vk, &vault_id, &med);

    assert_eq!(storage.count_items(&vault_id, ITEM_TYPE), 1);
    assert!(storage.delete_item(&item_id));
    assert_eq!(storage.count_items(&vault_id, ITEM_TYPE), 0);
}

#[test]
fn name_matching_substring() {
    let (_tmp, storage, vk, vault_id) = setup();

    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Lisinopril", "10mg", "tablet"),
    );
    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Aspirin", "81mg", "tablet"),
    );
    store_med(
        &storage,
        &vk,
        &vault_id,
        &make_med("Vitamin D", "2000IU", "softgel"),
    );

    let meds = list_meds(&storage, &vk, &vault_id);

    // Substring match "lisin" should find "Lisinopril" (case-insensitive)
    let query = "lisin";
    let lower = query.to_lowercase();
    let matches: Vec<_> = meds
        .iter()
        .filter(|(_id, m)| m.name.to_lowercase().contains(&lower))
        .collect();
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].1.name, "Lisinopril");

    // "in" matches both "Lisinopril" and "Vitamin D" (contains "in")
    let query2 = "in";
    let lower2 = query2.to_lowercase();
    let matches2: Vec<_> = meds
        .iter()
        .filter(|(_id, m)| m.name.to_lowercase().contains(&lower2))
        .collect();
    assert!(matches2.len() >= 2);
}

#[test]
fn full_crud_cycle() {
    let (_tmp, storage, vk, vault_id) = setup();

    // Create
    let med = make_med("Metformin", "500mg", "tablet");
    let item_id = store_med(&storage, &vk, &vault_id, &med);
    assert_eq!(storage.count_items(&vault_id, ITEM_TYPE), 1);

    // Read (list)
    let meds = list_meds(&storage, &vk, &vault_id);
    assert_eq!(meds.len(), 1);
    assert_eq!(meds[0].1.name, "Metformin");

    // Read (show)
    let loaded = load_med(&storage, &vk, &item_id);
    assert_eq!(loaded.dosage, "500mg");

    // Update
    let mut edited = loaded;
    edited.dosage = "1000mg".to_string();
    edited.notes = Some("Take with food".to_string());
    edited.updated_at = Utc::now();
    let blob = encrypt_json(&edited, &vk).unwrap();
    assert!(storage.update_item(&item_id, blob.to_bytes()));

    let after_edit = load_med(&storage, &vk, &item_id);
    assert_eq!(after_edit.dosage, "1000mg");
    assert_eq!(after_edit.notes, Some("Take with food".to_string()));

    // Delete
    assert!(storage.delete_item(&item_id));
    assert_eq!(storage.count_items(&vault_id, ITEM_TYPE), 0);
}
