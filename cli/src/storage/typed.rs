use pildora_crypto::key_hierarchy::VaultKey;
use pildora_crypto::vault::{EncryptedBlob, decrypt_json, encrypt_json};

use super::{Storage, StorageError};

/// Store a typed item: serialize to JSON → encrypt → store in database.
///
/// Returns the generated item ID.
pub fn store_typed_item<T: serde::Serialize>(
    storage: &Storage,
    vault_key: &VaultKey,
    vault_id: &str,
    item_type: &str,
    item: &T,
) -> Result<String, StorageError> {
    let blob = encrypt_json(item, vault_key)
        .map_err(|e| StorageError::Database(rusqlite::Error::ToSqlConversionFailure(e.into())))?;

    let id = uuid::Uuid::new_v4().to_string();
    storage.store_item(&id, vault_id, item_type, blob.to_bytes())?;
    Ok(id)
}

/// Load and decrypt a typed item by ID.
pub fn load_typed_item<T: serde::de::DeserializeOwned>(
    storage: &Storage,
    vault_key: &VaultKey,
    id: &str,
) -> Result<T, StorageError> {
    let row = storage.load_item(id)?;
    let blob = EncryptedBlob::from_bytes(row.encrypted_blob)
        .map_err(|e| StorageError::Database(rusqlite::Error::ToSqlConversionFailure(e.into())))?;
    let item: T = decrypt_json(&blob, vault_key)
        .map_err(|e| StorageError::Database(rusqlite::Error::ToSqlConversionFailure(e.into())))?;
    Ok(item)
}

/// List and decrypt all items of a given type in a vault.
///
/// Returns a vec of `(item_id, deserialized_item)` pairs.
pub fn list_typed_items<T: serde::de::DeserializeOwned>(
    storage: &Storage,
    vault_key: &VaultKey,
    vault_id: &str,
    item_type: &str,
) -> Result<Vec<(String, T)>, StorageError> {
    let rows = storage.list_item_rows(vault_id, Some(item_type))?;
    let mut items = Vec::with_capacity(rows.len());
    for row in rows {
        let blob = EncryptedBlob::from_bytes(row.encrypted_blob).map_err(|e| {
            StorageError::Database(rusqlite::Error::ToSqlConversionFailure(e.into()))
        })?;
        let item: T = decrypt_json(&blob, vault_key).map_err(|e| {
            StorageError::Database(rusqlite::Error::ToSqlConversionFailure(e.into()))
        })?;
        items.push((row.id, item));
    }
    Ok(items)
}
