use chrono::{NaiveTime, Utc};
use pildora_crypto::key_hierarchy;
use pildora_crypto::vault::{EncryptedBlob, decrypt_json, encrypt_json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Mirror types from the binary crate ──────────────────────────────────────

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
        start_date: chrono::NaiveDate,
    },
    SpecificDays {
        days: Vec<chrono::Weekday>,
    },
    Prn,
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
enum DoseStatus {
    Taken,
    Skipped,
}

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

fn make_schedule(med_name: &str) -> Schedule {
    let now = Utc::now();
    Schedule {
        medication_id: Uuid::new_v4().to_string(),
        medication_name: med_name.to_string(),
        pattern: SchedulePattern::Daily,
        times: vec![NaiveTime::from_hms_opt(8, 0, 0).unwrap()],
        created_at: now,
        updated_at: now,
    }
}

fn make_dose_log(med_name: &str, status: DoseStatus) -> DoseLog {
    let now = Utc::now();
    DoseLog {
        medication_id: Uuid::new_v4().to_string(),
        medication_name: med_name.to_string(),
        taken_at: now,
        status,
        notes: None,
        created_at: now,
    }
}

fn store_item<T: Serialize>(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
    item_type: &str,
    item: &T,
) -> String {
    let blob = encrypt_json(item, vk).unwrap();
    let item_id = Uuid::new_v4().to_string();
    storage.store_item(&item_id, vault_id, item_type, blob.to_bytes());
    item_id
}

fn load_all<T: serde::de::DeserializeOwned>(
    storage: &Storage,
    vk: &key_hierarchy::VaultKey,
    vault_id: &str,
    item_type: &str,
) -> Vec<T> {
    storage
        .list_items(vault_id, item_type)
        .into_iter()
        .map(|row| {
            let blob = EncryptedBlob::from_bytes(row.encrypted_blob).unwrap();
            decrypt_json(&blob, vk).unwrap()
        })
        .collect()
}

// ── Export helper (mirrors src/export.rs logic) ─────────────────────────────

#[derive(Debug, Serialize)]
struct ExportData {
    metadata: ExportMetadata,
    medications: Vec<Medication>,
    schedules: Vec<Schedule>,
    dose_logs: Vec<DoseLog>,
}

#[derive(Debug, Serialize)]
struct ExportMetadata {
    export_date: String,
    vault_name: String,
    pildora_version: String,
    medication_count: usize,
    schedule_count: usize,
    dose_log_count: usize,
}

fn csv_escape(field: &str) -> String {
    if field.contains(',') || field.contains('"') || field.contains('\n') || field.contains('\r') {
        let escaped = field.replace('"', "\"\"");
        format!("\"{escaped}\"")
    } else {
        field.to_string()
    }
}

fn medications_to_csv(meds: &[Medication]) -> String {
    let mut out = String::from(
        "name,generic_name,brand_name,dosage,form,prescriber,pharmacy,notes,start_date,end_date\n",
    );
    for med in meds {
        let row = [
            csv_escape(&med.name),
            csv_escape(med.generic_name.as_deref().unwrap_or("")),
            csv_escape(med.brand_name.as_deref().unwrap_or("")),
            csv_escape(&med.dosage),
            csv_escape(&med.form),
            csv_escape(med.prescriber.as_deref().unwrap_or("")),
            csv_escape(med.pharmacy.as_deref().unwrap_or("")),
            csv_escape(med.notes.as_deref().unwrap_or("")),
            csv_escape(med.start_date.as_deref().unwrap_or("")),
            csv_escape(med.end_date.as_deref().unwrap_or("")),
        ];
        out.push_str(&row.join(","));
        out.push('\n');
    }
    out
}

fn dose_logs_to_csv(logs: &[DoseLog]) -> String {
    let mut out = String::from("medication_name,taken_at,status,notes\n");
    for log in logs {
        let status = match log.status {
            DoseStatus::Taken => "taken",
            DoseStatus::Skipped => "skipped",
        };
        let row = [
            csv_escape(&log.medication_name),
            csv_escape(&log.taken_at.to_rfc3339()),
            csv_escape(status),
            csv_escape(log.notes.as_deref().unwrap_or("")),
        ];
        out.push_str(&row.join(","));
        out.push('\n');
    }
    out
}

fn to_json(data: &ExportData) -> String {
    serde_json::to_string_pretty(data).unwrap()
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[test]
fn json_export_roundtrip() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med1 = make_med("Aspirin", "81mg", "tablet");
    let med2 = make_med("Vitamin D", "2000IU", "softgel");
    store_item(&storage, &vk, &vault_id, "medication", &med1);
    store_item(&storage, &vk, &vault_id, "medication", &med2);

    let sched = make_schedule("Aspirin");
    store_item(&storage, &vk, &vault_id, "schedule", &sched);

    let log1 = make_dose_log("Aspirin", DoseStatus::Taken);
    let log2 = make_dose_log("Vitamin D", DoseStatus::Skipped);
    store_item(&storage, &vk, &vault_id, "dose_log", &log1);
    store_item(&storage, &vk, &vault_id, "dose_log", &log2);

    // Load all items back (simulating what the export command does)
    let meds: Vec<Medication> = load_all(&storage, &vk, &vault_id, "medication");
    let schedules: Vec<Schedule> = load_all(&storage, &vk, &vault_id, "schedule");
    let dose_logs: Vec<DoseLog> = load_all(&storage, &vk, &vault_id, "dose_log");

    let data = ExportData {
        metadata: ExportMetadata {
            export_date: Utc::now().to_rfc3339(),
            vault_name: "My Meds".to_string(),
            pildora_version: "0.1.0".to_string(),
            medication_count: meds.len(),
            schedule_count: schedules.len(),
            dose_log_count: dose_logs.len(),
        },
        medications: meds,
        schedules,
        dose_logs,
    };

    let json = to_json(&data);
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(parsed["medications"].as_array().unwrap().len(), 2);
    assert_eq!(parsed["schedules"].as_array().unwrap().len(), 1);
    assert_eq!(parsed["dose_logs"].as_array().unwrap().len(), 2);
    assert_eq!(parsed["medications"][0]["name"], "Aspirin");
    assert_eq!(parsed["medications"][1]["name"], "Vitamin D");
}

#[test]
fn json_metadata_fields() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med = make_med("Ibuprofen", "200mg", "tablet");
    store_item(&storage, &vk, &vault_id, "medication", &med);

    let meds: Vec<Medication> = load_all(&storage, &vk, &vault_id, "medication");

    let data = ExportData {
        metadata: ExportMetadata {
            export_date: Utc::now().to_rfc3339(),
            vault_name: "My Meds".to_string(),
            pildora_version: "0.1.0".to_string(),
            medication_count: meds.len(),
            schedule_count: 0,
            dose_log_count: 0,
        },
        medications: meds,
        schedules: vec![],
        dose_logs: vec![],
    };

    let json = to_json(&data);
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

    let meta = &parsed["metadata"];
    assert_eq!(meta["vault_name"], "My Meds");
    assert_eq!(meta["pildora_version"], "0.1.0");
    assert_eq!(meta["medication_count"], 1);
    assert_eq!(meta["schedule_count"], 0);
    assert_eq!(meta["dose_log_count"], 0);
    // export_date should be an ISO 8601 / RFC 3339 timestamp
    assert!(meta["export_date"].as_str().unwrap().contains('T'));
}

#[test]
fn csv_medications_header_and_rows() {
    let (_tmp, storage, vk, vault_id) = setup();

    let med1 = make_med("Aspirin", "81mg", "tablet");
    let med2 = make_med("Vitamin D", "2000IU", "softgel");
    store_item(&storage, &vk, &vault_id, "medication", &med1);
    store_item(&storage, &vk, &vault_id, "medication", &med2);

    let meds: Vec<Medication> = load_all(&storage, &vk, &vault_id, "medication");
    let csv = medications_to_csv(&meds);
    let lines: Vec<&str> = csv.lines().collect();

    assert_eq!(
        lines[0],
        "name,generic_name,brand_name,dosage,form,prescriber,pharmacy,notes,start_date,end_date"
    );
    assert_eq!(lines.len(), 3); // header + 2 data rows
    assert!(lines[1].starts_with("Aspirin,"));
    assert!(lines[2].starts_with("Vitamin D,"));
}

#[test]
fn csv_dose_logs_format() {
    let log1 = make_dose_log("Aspirin", DoseStatus::Taken);
    let log2 = make_dose_log("Vitamin D", DoseStatus::Skipped);

    let csv = dose_logs_to_csv(&[log1, log2]);
    let lines: Vec<&str> = csv.lines().collect();

    assert_eq!(lines[0], "medication_name,taken_at,status,notes");
    assert_eq!(lines.len(), 3);
    assert!(lines[1].contains("Aspirin"));
    assert!(lines[1].contains("taken"));
    assert!(lines[2].contains("Vitamin D"));
    assert!(lines[2].contains("skipped"));
}

#[test]
fn empty_vault_export() {
    let (_tmp, storage, vk, vault_id) = setup();

    let meds: Vec<Medication> = load_all(&storage, &vk, &vault_id, "medication");
    let schedules: Vec<Schedule> = load_all(&storage, &vk, &vault_id, "schedule");
    let dose_logs: Vec<DoseLog> = load_all(&storage, &vk, &vault_id, "dose_log");

    let data = ExportData {
        metadata: ExportMetadata {
            export_date: Utc::now().to_rfc3339(),
            vault_name: "My Meds".to_string(),
            pildora_version: "0.1.0".to_string(),
            medication_count: meds.len(),
            schedule_count: schedules.len(),
            dose_log_count: dose_logs.len(),
        },
        medications: meds,
        schedules,
        dose_logs,
    };

    let json = to_json(&data);
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert!(parsed["medications"].as_array().unwrap().is_empty());
    assert!(parsed["schedules"].as_array().unwrap().is_empty());
    assert!(parsed["dose_logs"].as_array().unwrap().is_empty());
    assert_eq!(parsed["metadata"]["medication_count"], 0);
}

#[test]
fn csv_escaping_commas_and_quotes() {
    let mut med = make_med("Med, with comma", "10mg", "tablet");
    med.notes = Some("has \"quotes\" and,commas".to_string());

    let csv = medications_to_csv(&[med]);
    let lines: Vec<&str> = csv.lines().collect();
    let row = lines[1];

    // Name with comma should be double-quoted
    assert!(row.starts_with("\"Med, with comma\""));
    // Notes with quotes and commas should be properly escaped
    assert!(row.contains("\"has \"\"quotes\"\" and,commas\""));
}
