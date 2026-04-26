use std::process;

use colored::Colorize;
use pildora_crypto::key_hierarchy::{self, MasterEncryptionKey, VaultKey, WrappedVaultKey};
use uuid::Uuid;

use crate::models::Medication;
use crate::session::Session;
use crate::storage::Storage;
use crate::storage::typed::list_typed_items;

/// Holds the unlocked vault context needed by data commands.
pub struct UnlockedContext {
    pub storage: Storage,
    pub vault_key: VaultKey,
    pub vault_id: String,
}

impl UnlockedContext {
    /// Open storage, verify session is active, reconstruct VK.
    /// Exits with error message if vault is locked or not initialized.
    pub fn require() -> Self {
        let data_dir = crate::storage::default_data_dir();
        let storage = Storage::open(&data_dir).unwrap_or_else(|e| {
            eprintln!("{} Failed to open storage: {e}", "\u{2717}".red());
            process::exit(1);
        });

        if !storage.is_initialized().unwrap_or(false) {
            eprintln!("Not initialized. Run 'pildora init' first.");
            process::exit(1);
        }

        let session = Session::new(&data_dir);
        let mek_bytes = session
            .load_mek()
            .unwrap_or_else(|e| {
                eprintln!("{} Session error: {e}", "\u{2717}".red());
                process::exit(1);
            })
            .unwrap_or_else(|| {
                eprintln!("Vault is locked. Run 'pildora unlock' first.");
                process::exit(1);
            });

        let mut mek_arr = [0u8; 32];
        mek_arr.copy_from_slice(&mek_bytes);
        let mek = MasterEncryptionKey::from_bytes(mek_arr);

        let vault_ids = storage.list_vault_ids().unwrap_or_else(|e| {
            eprintln!("{} Failed to list vaults: {e}", "\u{2717}".red());
            process::exit(1);
        });

        let vault_id = vault_ids.into_iter().next().unwrap_or_else(|| {
            eprintln!("{} No vaults found.", "\u{2717}".red());
            process::exit(1);
        });

        let wrapped_vk_bytes = storage
            .get_wrapped_vault_key(&vault_id)
            .unwrap_or_else(|e| {
                eprintln!("{} Failed to get vault key: {e}", "\u{2717}".red());
                process::exit(1);
            });
        let wvk = WrappedVaultKey(wrapped_vk_bytes);
        let vault_key = key_hierarchy::unwrap_vault_key(&wvk, &mek).unwrap_or_else(|e| {
            eprintln!("{} Failed to unwrap vault key: {e}", "\u{2717}".red());
            eprintln!("  Session may be stale. Try 'pildora lock' then 'pildora unlock'.");
            process::exit(1);
        });

        Self {
            storage,
            vault_key,
            vault_id,
        }
    }

    /// Find a medication by case-insensitive substring match on name.
    ///
    /// Exits with an error if zero or multiple matches are found.
    pub fn find_medication(&self, query: &str) -> (String, Medication) {
        let meds: Vec<(String, Medication)> =
            list_typed_items(&self.storage, &self.vault_key, &self.vault_id, "medication")
                .unwrap_or_else(|e| {
                    eprintln!("{} Failed to list medications: {e}", "\u{2717}".red());
                    process::exit(1);
                });

        // Try exact UUID match first
        if let Ok(parsed_uuid) = Uuid::parse_str(query) {
            let uuid_str = parsed_uuid.to_string();
            for (item_id, med) in &meds {
                if med.id.to_string() == uuid_str {
                    return (item_id.clone(), med.clone());
                }
            }
        }

        let lower = query.to_lowercase();
        let matches: Vec<(String, Medication)> = meds
            .into_iter()
            .filter(|(_id, m)| m.name.to_lowercase().contains(&lower))
            .collect();

        match matches.len() {
            0 => {
                eprintln!("No medication found matching '{query}'.");
                process::exit(1);
            }
            1 => matches.into_iter().next().unwrap(),
            _ => {
                eprintln!("Multiple medications match '{query}':");
                for (_id, m) in &matches {
                    eprintln!("  - {}", m.name);
                }
                eprintln!("Please be more specific.");
                process::exit(1);
            }
        }
    }
}
