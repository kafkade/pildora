use colored::Colorize;

use crate::session::Session;
use crate::storage::Storage;

pub fn run() {
    let data_dir = crate::storage::default_data_dir();

    let Ok(store) = Storage::open(&data_dir) else {
        println!("Not initialized. Run 'pildora init'.");
        return;
    };

    if !store.is_initialized().unwrap_or(false) {
        println!("Not initialized. Run 'pildora init'.");
        return;
    }

    let session = Session::new(&data_dir);
    let locked = !session.is_active();

    println!("{}", "Pildora Status".bold());
    if locked {
        println!("  Vault: {}", "🔒 Locked".red());
    } else {
        println!("  Vault: {}", "🔓 Unlocked".green());
    }

    let vault_ids = store.list_vault_ids().unwrap_or_default();
    println!("  Vaults: {}", vault_ids.len());

    if let Some(vault_id) = vault_ids.first() {
        let med_count = store.count_items(vault_id, Some("medication")).unwrap_or(0);
        let dose_count = store.count_items(vault_id, Some("dose_log")).unwrap_or(0);
        println!("  Medications: {med_count}");
        println!("  Dose logs: {dose_count}");
    }
}
