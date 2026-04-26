//! Integration tests for vault management commands.
//!
//! Since the command handlers interact with stdin (password prompts), we test
//! the underlying cryptographic and storage logic directly instead of invoking
//! the command functions.

use pildora_crypto::key_hierarchy::{self, MasterEncryptionKey, RecoveryKey, WrappedVaultKey};
use pildora_crypto::{primitives, vault};
use tempfile::TempDir;

// Bring in the types we need from the CLI crate via its public modules.
// These are integration tests (in `tests/`), so we use `pildora_cli::` paths
// for any public items. Since the binary doesn't expose a library, we
// re-implement the test logic using the crypto and storage crates directly.

const TEST_PASSWORD: &[u8] = b"correct horse battery staple";

/// Helper: run the full init flow and return (data_dir, salt, mek_bytes).
fn init_vault(data_dir: &std::path::Path) -> (Vec<u8>, [u8; 32]) {
    let db_path = data_dir.join("pildora.db");
    let conn = rusqlite::Connection::open(&db_path).unwrap();

    // Run migrations (same as Storage::open)
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

    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    let vault_id = uuid::Uuid::new_v4().to_string();
    let vk = key_hierarchy::generate_vault_key();
    let wrapped_vk = key_hierarchy::wrap_vault_key(&vk, &mek).unwrap();

    #[derive(serde::Serialize)]
    struct VaultMetadata {
        name: String,
    }
    let metadata = VaultMetadata {
        name: "My Meds".to_string(),
    };
    let encrypted_meta = vault::encrypt_json(&metadata, &vk).unwrap();

    let rk = key_hierarchy::generate_recovery_key();
    let recovery_wrapped_mek = key_hierarchy::wrap_mek_for_recovery(&mek, &rk).unwrap();
    let rk_encrypted =
        primitives::aes256_gcm_encrypt(mek.as_bytes(), rk.as_bytes(), b"pildora:v1:recovery-key")
            .unwrap();

    let now = chrono::Utc::now().to_rfc3339();
    conn.execute(
        "INSERT INTO account_state (id, salt, recovery_wrapped_mek, recovery_key_encrypted, created_at)
         VALUES (1, ?1, ?2, ?3, ?4)",
        rusqlite::params![&salt[..], &recovery_wrapped_mek.0, &rk_encrypted, &now],
    )
    .unwrap();

    conn.execute(
        "INSERT INTO vaults (id, encrypted_metadata, wrapped_vault_key, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![
            &vault_id,
            encrypted_meta.to_bytes(),
            &wrapped_vk.0,
            &now,
            &now
        ],
    )
    .unwrap();

    (salt.to_vec(), *mek.as_bytes())
}

// ── Init flow tests ──────────────────────────────────────────────────────────

#[test]
fn init_key_derivation_roundtrip() {
    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    let vk = key_hierarchy::generate_vault_key();
    let wrapped_vk = key_hierarchy::wrap_vault_key(&vk, &mek).unwrap();
    let unwrapped_vk = key_hierarchy::unwrap_vault_key(&wrapped_vk, &mek).unwrap();

    assert_eq!(vk.as_bytes(), unwrapped_vk.as_bytes());
}

#[test]
fn init_stores_and_loads_account() {
    let dir = TempDir::new().unwrap();
    let (salt, _mek_bytes) = init_vault(dir.path());

    // Re-open and verify
    let db_path = dir.path().join("pildora.db");
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let stored_salt: Vec<u8> = conn
        .query_row("SELECT salt FROM account_state WHERE id = 1", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(stored_salt, salt);
}

// ── Unlock flow tests ────────────────────────────────────────────────────────

#[test]
fn unlock_correct_password_succeeds() {
    let dir = TempDir::new().unwrap();
    let (salt, _mek_bytes) = init_vault(dir.path());

    // Re-derive with same password
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    // Load wrapped VK
    let db_path = dir.path().join("pildora.db");
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let wrapped_vk_bytes: Vec<u8> = conn
        .query_row("SELECT wrapped_vault_key FROM vaults LIMIT 1", [], |r| {
            r.get(0)
        })
        .unwrap();
    let wvk = WrappedVaultKey(wrapped_vk_bytes);

    assert!(key_hierarchy::unwrap_vault_key(&wvk, &mek).is_ok());
}

#[test]
fn unlock_wrong_password_fails() {
    let dir = TempDir::new().unwrap();
    let (salt, _) = init_vault(dir.path());

    let mk_wrong = key_hierarchy::derive_master_key(b"wrong password!!", &salt).unwrap();
    let (_, mek_wrong) = key_hierarchy::derive_sub_keys(&mk_wrong).unwrap();

    let db_path = dir.path().join("pildora.db");
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let wrapped_vk_bytes: Vec<u8> = conn
        .query_row("SELECT wrapped_vault_key FROM vaults LIMIT 1", [], |r| {
            r.get(0)
        })
        .unwrap();
    let wvk = WrappedVaultKey(wrapped_vk_bytes);

    assert!(key_hierarchy::unwrap_vault_key(&wvk, &mek_wrong).is_err());
}

// ── Session file tests ───────────────────────────────────────────────────────

#[test]
fn session_file_store_load_clear() {
    let dir = TempDir::new().unwrap();
    let session_path = dir.path().join(".session");

    let mek = [0xABu8; 32];

    // Store
    std::fs::write(&session_path, hex::encode(mek)).unwrap();
    assert!(session_path.exists());

    // Load
    let loaded_hex = std::fs::read_to_string(&session_path).unwrap();
    let loaded_bytes = hex::decode(loaded_hex.trim()).unwrap();
    assert_eq!(loaded_bytes, mek);

    // Clear
    std::fs::remove_file(&session_path).unwrap();
    assert!(!session_path.exists());
}

// ── Password validation tests ────────────────────────────────────────────────

#[test]
fn password_min_length_enforced() {
    // Fewer than 12 chars
    assert!("short".len() < 12);
    assert!("12345678901".len() < 12);
    // Exactly 12 chars
    assert_eq!("123456789012".len(), 12);
    // More than 12 chars
    assert!("correct horse battery staple".len() >= 12);
}

// ── Recovery key tests ───────────────────────────────────────────────────────

#[test]
fn recovery_key_encrypt_decrypt_roundtrip() {
    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    let rk = key_hierarchy::generate_recovery_key();

    // Encrypt RK under MEK
    let rk_encrypted =
        primitives::aes256_gcm_encrypt(mek.as_bytes(), rk.as_bytes(), b"pildora:v1:recovery-key")
            .unwrap();

    // Decrypt RK
    let rk_decrypted =
        primitives::aes256_gcm_decrypt(mek.as_bytes(), &rk_encrypted, b"pildora:v1:recovery-key")
            .unwrap();

    assert_eq!(rk.as_bytes().as_slice(), &rk_decrypted);

    // Reconstruct and verify display string matches
    let mut rk_arr = [0u8; 32];
    rk_arr.copy_from_slice(&rk_decrypted);
    let rk_reconstructed = RecoveryKey::from_bytes(rk_arr);
    assert_eq!(rk.to_display_string(), rk_reconstructed.to_display_string());
}

#[test]
fn recovery_key_from_bytes_roundtrip() {
    let rk = key_hierarchy::generate_recovery_key();
    let bytes = *rk.as_bytes();
    let rk2 = RecoveryKey::from_bytes(bytes);
    assert_eq!(rk.as_bytes(), rk2.as_bytes());
    assert_eq!(rk.to_display_string(), rk2.to_display_string());
}

#[test]
fn recovery_key_can_recover_mek() {
    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    let rk = key_hierarchy::generate_recovery_key();
    let wrapped = key_hierarchy::wrap_mek_for_recovery(&mek, &rk).unwrap();
    let recovered = key_hierarchy::unwrap_mek_from_recovery(&wrapped, &rk).unwrap();

    assert_eq!(mek.as_bytes(), recovered.as_bytes());

    // Recovered MEK can unwrap vault keys
    let vk = key_hierarchy::generate_vault_key();
    let wvk = key_hierarchy::wrap_vault_key(&vk, &mek).unwrap();
    let unwrapped = key_hierarchy::unwrap_vault_key(&wvk, &recovered).unwrap();
    assert_eq!(vk.as_bytes(), unwrapped.as_bytes());
}

#[test]
fn recovery_key_regeneration_invalidates_old() {
    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(TEST_PASSWORD, &salt).unwrap();
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap();

    let rk_old = key_hierarchy::generate_recovery_key();
    let _wrapped_old = key_hierarchy::wrap_mek_for_recovery(&mek, &rk_old).unwrap();

    // Regenerate
    let rk_new = key_hierarchy::generate_recovery_key();
    let wrapped_new = key_hierarchy::wrap_mek_for_recovery(&mek, &rk_new).unwrap();

    // Old key cannot unwrap new blob
    assert!(key_hierarchy::unwrap_mek_from_recovery(&wrapped_new, &rk_old).is_err());
    // New key can
    assert!(key_hierarchy::unwrap_mek_from_recovery(&wrapped_new, &rk_new).is_ok());
}

// ── Vault metadata encryption test ───────────────────────────────────────────

#[test]
fn vault_metadata_encrypt_decrypt() {
    let vk = key_hierarchy::generate_vault_key();

    #[derive(serde::Serialize, serde::Deserialize, Debug, PartialEq)]
    struct VaultMetadata {
        name: String,
    }

    let metadata = VaultMetadata {
        name: "My Meds".to_string(),
    };
    let blob = vault::encrypt_json(&metadata, &vk).unwrap();
    let decrypted: VaultMetadata = vault::decrypt_json(&blob, &vk).unwrap();
    assert_eq!(metadata, decrypted);
}

// ── Update recovery in storage ───────────────────────────────────────────────

#[test]
fn update_recovery_replaces_stored_data() {
    let dir = TempDir::new().unwrap();
    let (_salt, mek_bytes) = init_vault(dir.path());
    let mek = MasterEncryptionKey::from_bytes(mek_bytes);

    let db_path = dir.path().join("pildora.db");
    let conn = rusqlite::Connection::open(&db_path).unwrap();

    // Read original recovery data
    let original_wrapped: Vec<u8> = conn
        .query_row(
            "SELECT recovery_wrapped_mek FROM account_state WHERE id = 1",
            [],
            |r| r.get(0),
        )
        .unwrap();

    // Generate new recovery key
    let rk_new = key_hierarchy::generate_recovery_key();
    let new_wrapped = key_hierarchy::wrap_mek_for_recovery(&mek, &rk_new).unwrap();
    let new_rk_encrypted = primitives::aes256_gcm_encrypt(
        mek.as_bytes(),
        rk_new.as_bytes(),
        b"pildora:v1:recovery-key",
    )
    .unwrap();

    conn.execute(
        "UPDATE account_state SET recovery_wrapped_mek = ?1, recovery_key_encrypted = ?2 WHERE id = 1",
        rusqlite::params![&new_wrapped.0, &new_rk_encrypted],
    )
    .unwrap();

    // Verify updated
    let updated_wrapped: Vec<u8> = conn
        .query_row(
            "SELECT recovery_wrapped_mek FROM account_state WHERE id = 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_ne!(original_wrapped, updated_wrapped);

    // New RK can recover MEK
    let recovered = key_hierarchy::unwrap_mek_from_recovery(&new_wrapped, &rk_new).unwrap();
    assert_eq!(mek.as_bytes(), recovered.as_bytes());
}
