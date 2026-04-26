use chrono::{NaiveDate, NaiveTime, Utc, Weekday};
use serde::{Deserialize, Serialize};

// ── Mirror types from the binary crate ──────────────────────────────────────
// Integration tests cannot import from a binary crate, so we replicate the
// schedule models needed for testing.

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Schedule {
    medication_id: String,
    medication_name: String,
    pattern: SchedulePattern,
    times: Vec<NaiveTime>,
    created_at: chrono::DateTime<Utc>,
    updated_at: chrono::DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum SchedulePattern {
    Daily,
    EveryNDays {
        interval: u32,
        start_date: NaiveDate,
    },
    SpecificDays {
        days: Vec<Weekday>,
    },
    Prn,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
enum DoseStatus {
    Taken,
    Skipped,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DoseLog {
    medication_id: String,
    medication_name: String,
    taken_at: chrono::DateTime<Utc>,
    status: DoseStatus,
    notes: Option<String>,
    created_at: chrono::DateTime<Utc>,
}

// ── Minimal test storage ────────────────────────────────────────────────────

mod test_storage {
    use chrono::Utc;
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
            let now = Utc::now().to_rfc3339();
            self.conn
                .execute(
                    "INSERT INTO encrypted_items \
                     (id, vault_id, item_type, encrypted_blob, blob_version, created_at, updated_at) \
                     VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6)",
                    params![id, vault_id, item_type, blob, now, now],
                )
                .unwrap();
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

        pub fn create_vault(&self, id: &str) {
            let now = Utc::now().to_rfc3339();
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

use pildora_crypto::key_hierarchy;
use pildora_crypto::vault::{EncryptedBlob, decrypt_json, encrypt_json};
use test_storage::Storage;

// ── Helpers ─────────────────────────────────────────────────────────────────

fn setup() -> (tempfile::TempDir, Storage, key_hierarchy::VaultKey, String) {
    let tmp = tempfile::tempdir().unwrap();
    let storage = Storage::open(tmp.path());
    let vault_id = uuid::Uuid::new_v4().to_string();
    storage.create_vault(&vault_id);
    let vk = key_hierarchy::generate_vault_key();
    (tmp, storage, vk, vault_id)
}

fn store_item<T: serde::Serialize>(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
    item_type: &str,
    item: &T,
) -> String {
    let blob = encrypt_json(item, vk).unwrap();
    let item_id = uuid::Uuid::new_v4().to_string();
    storage.store_item(&item_id, vault_id, item_type, blob.to_bytes());
    item_id
}

fn list_items<T: serde::de::DeserializeOwned>(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
    item_type: &str,
) -> Vec<(String, T)> {
    storage
        .list_items(vault_id, item_type)
        .into_iter()
        .map(|row| {
            let blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
            let item: T = decrypt_json(&blob, vk).unwrap();
            (row.id, item)
        })
        .collect()
}

fn make_schedule(
    med_id: &str,
    med_name: &str,
    pattern: SchedulePattern,
    times: Vec<NaiveTime>,
) -> Schedule {
    let now = Utc::now();
    Schedule {
        medication_id: med_id.to_string(),
        medication_name: med_name.to_string(),
        pattern,
        times,
        created_at: now,
        updated_at: now,
    }
}

fn make_dose_log(med_id: &str, med_name: &str, status: DoseStatus, notes: Option<&str>) -> DoseLog {
    let now = Utc::now();
    DoseLog {
        medication_id: med_id.to_string(),
        medication_name: med_name.to_string(),
        taken_at: now,
        status,
        notes: notes.map(String::from),
        created_at: now,
    }
}

// ── Schedule serialization tests ────────────────────────────────────────────

#[test]
fn schedule_store_and_load_daily() {
    let (_tmp, storage, vk, vault_id) = setup();

    let schedule = make_schedule(
        "med-1",
        "Lisinopril",
        SchedulePattern::Daily,
        vec![
            NaiveTime::from_hms_opt(8, 0, 0).unwrap(),
            NaiveTime::from_hms_opt(20, 0, 0).unwrap(),
        ],
    );

    store_item(&storage, &vk, &vault_id, "schedule", &schedule);

    let loaded: Vec<(String, Schedule)> = list_items(&storage, &vk, &vault_id, "schedule");
    assert_eq!(loaded.len(), 1);

    let (_, s) = &loaded[0];
    assert_eq!(s.medication_name, "Lisinopril");
    assert_eq!(s.times.len(), 2);
    assert!(matches!(s.pattern, SchedulePattern::Daily));
}

#[test]
fn schedule_store_and_load_every_n_days() {
    let (_tmp, storage, vk, vault_id) = setup();

    let start = NaiveDate::from_ymd_opt(2026, 4, 25).unwrap();
    let schedule = make_schedule(
        "med-2",
        "Metformin",
        SchedulePattern::EveryNDays {
            interval: 3,
            start_date: start,
        },
        vec![NaiveTime::from_hms_opt(9, 0, 0).unwrap()],
    );

    store_item(&storage, &vk, &vault_id, "schedule", &schedule);

    let loaded: Vec<(String, Schedule)> = list_items(&storage, &vk, &vault_id, "schedule");
    assert_eq!(loaded.len(), 1);

    let (_, s) = &loaded[0];
    match &s.pattern {
        SchedulePattern::EveryNDays {
            interval,
            start_date,
        } => {
            assert_eq!(*interval, 3);
            assert_eq!(*start_date, start);
        }
        other => panic!("Expected EveryNDays, got {other:?}"),
    }
}

#[test]
fn schedule_store_and_load_specific_days() {
    let (_tmp, storage, vk, vault_id) = setup();

    let schedule = make_schedule(
        "med-3",
        "Vitamin D",
        SchedulePattern::SpecificDays {
            days: vec![Weekday::Mon, Weekday::Wed, Weekday::Fri],
        },
        vec![NaiveTime::from_hms_opt(8, 0, 0).unwrap()],
    );

    store_item(&storage, &vk, &vault_id, "schedule", &schedule);

    let loaded: Vec<(String, Schedule)> = list_items(&storage, &vk, &vault_id, "schedule");
    assert_eq!(loaded.len(), 1);

    let (_, s) = &loaded[0];
    match &s.pattern {
        SchedulePattern::SpecificDays { days } => {
            assert_eq!(days.len(), 3);
            assert!(days.contains(&Weekday::Mon));
            assert!(days.contains(&Weekday::Wed));
            assert!(days.contains(&Weekday::Fri));
        }
        other => panic!("Expected SpecificDays, got {other:?}"),
    }
}

#[test]
fn schedule_store_and_load_prn() {
    let (_tmp, storage, vk, vault_id) = setup();

    let schedule = make_schedule("med-4", "Ibuprofen", SchedulePattern::Prn, vec![]);

    store_item(&storage, &vk, &vault_id, "schedule", &schedule);

    let loaded: Vec<(String, Schedule)> = list_items(&storage, &vk, &vault_id, "schedule");
    assert_eq!(loaded.len(), 1);

    let (_, s) = &loaded[0];
    assert!(matches!(s.pattern, SchedulePattern::Prn));
    assert!(s.times.is_empty());
}

// ── Dose log tests ──────────────────────────────────────────────────────────

#[test]
fn dose_log_store_taken() {
    let (_tmp, storage, vk, vault_id) = setup();

    let log = make_dose_log("med-1", "Lisinopril", DoseStatus::Taken, None);
    store_item(&storage, &vk, &vault_id, "dose_log", &log);

    let loaded: Vec<(String, DoseLog)> = list_items(&storage, &vk, &vault_id, "dose_log");
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].1.status, DoseStatus::Taken);
    assert_eq!(loaded[0].1.medication_name, "Lisinopril");
    assert!(loaded[0].1.notes.is_none());
}

#[test]
fn dose_log_store_skipped_with_reason() {
    let (_tmp, storage, vk, vault_id) = setup();

    let log = make_dose_log(
        "med-1",
        "Lisinopril",
        DoseStatus::Skipped,
        Some("out of stock"),
    );
    store_item(&storage, &vk, &vault_id, "dose_log", &log);

    let loaded: Vec<(String, DoseLog)> = list_items(&storage, &vk, &vault_id, "dose_log");
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].1.status, DoseStatus::Skipped);
    assert_eq!(loaded[0].1.notes.as_deref(), Some("out of stock"));
}

#[test]
fn dose_log_list_multiple() {
    let (_tmp, storage, vk, vault_id) = setup();

    store_item(
        &storage,
        &vk,
        &vault_id,
        "dose_log",
        &make_dose_log("med-1", "Lisinopril", DoseStatus::Taken, None),
    );
    store_item(
        &storage,
        &vk,
        &vault_id,
        "dose_log",
        &make_dose_log("med-2", "Metformin", DoseStatus::Taken, None),
    );
    store_item(
        &storage,
        &vk,
        &vault_id,
        "dose_log",
        &make_dose_log("med-1", "Lisinopril", DoseStatus::Skipped, Some("forgot")),
    );

    let loaded: Vec<(String, DoseLog)> = list_items(&storage, &vk, &vault_id, "dose_log");
    assert_eq!(loaded.len(), 3);
}

#[test]
fn full_flow_schedule_and_dose() {
    let (_tmp, storage, vk, vault_id) = setup();

    // Store a schedule
    let schedule = make_schedule(
        "med-1",
        "Lisinopril",
        SchedulePattern::Daily,
        vec![
            NaiveTime::from_hms_opt(8, 0, 0).unwrap(),
            NaiveTime::from_hms_opt(20, 0, 0).unwrap(),
        ],
    );
    store_item(&storage, &vk, &vault_id, "schedule", &schedule);

    // Log a dose
    let dose = make_dose_log("med-1", "Lisinopril", DoseStatus::Taken, None);
    store_item(&storage, &vk, &vault_id, "dose_log", &dose);

    // Verify both exist
    let schedules: Vec<(String, Schedule)> = list_items(&storage, &vk, &vault_id, "schedule");
    assert_eq!(schedules.len(), 1);

    let logs: Vec<(String, DoseLog)> = list_items(&storage, &vk, &vault_id, "dose_log");
    assert_eq!(logs.len(), 1);
    assert_eq!(logs[0].1.medication_id, schedules[0].1.medication_id);
}
