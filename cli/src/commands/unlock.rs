use std::process;

use colored::Colorize;
use pildora_crypto::key_hierarchy::{self, WrappedVaultKey};

use crate::session::Session;
use crate::storage::Storage;

pub fn run() {
    let data_dir = crate::storage::default_data_dir();
    let store = Storage::open(&data_dir).unwrap_or_else(|e| {
        eprintln!("{} Failed to open storage: {e}", "✗".red());
        process::exit(1);
    });

    let account = store
        .load_account()
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to load account: {e}", "✗".red());
            process::exit(1);
        })
        .unwrap_or_else(|| {
            eprintln!("Not initialized. Run 'pildora init' first.");
            process::exit(1);
        });

    // Check if already unlocked
    let session = Session::new(&data_dir);
    if session.is_active() {
        println!("{} Vault is already unlocked.", "✓".green());
        return;
    }

    let password = rpassword::prompt_password_stderr("Master password: ").unwrap_or_else(|e| {
        eprintln!("{} Failed to read password: {e}", "✗".red());
        process::exit(1);
    });

    // Derive keys using stored parameters
    let mk = pildora_crypto::primitives::derive_key_argon2id_with_params(
        password.as_bytes(),
        &account.salt,
        account.argon2_memory_kib,
        account.argon2_iterations,
        account.argon2_parallelism,
    )
    .unwrap_or_else(|e| {
        eprintln!("{} Key derivation failed: {e}", "✗".red());
        process::exit(1);
    });
    let master_key = key_hierarchy::MasterKey::from_bytes(mk);
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&master_key).unwrap_or_else(|e| {
        eprintln!("{} Sub-key derivation failed: {e}", "✗".red());
        process::exit(1);
    });

    // Verify by trying to unwrap a vault key
    let vault_ids = store.list_vault_ids().unwrap_or_else(|e| {
        eprintln!("{} Failed to list vaults: {e}", "✗".red());
        process::exit(1);
    });

    if let Some(vault_id) = vault_ids.first() {
        let wrapped_vk_bytes = store.get_wrapped_vault_key(vault_id).unwrap_or_else(|e| {
            eprintln!("{} Failed to get vault key: {e}", "✗".red());
            process::exit(1);
        });
        let wvk = WrappedVaultKey(wrapped_vk_bytes);
        if key_hierarchy::unwrap_vault_key(&wvk, &mek).is_ok() {
            session.store_mek(mek.as_bytes()).ok();
            println!("{} Vault unlocked.", "✓".green());
        } else {
            eprintln!("{} Wrong password.", "✗".red());
            eprintln!("  If you've forgotten your password, use your recovery key.");
            process::exit(1);
        }
    } else {
        // No vaults — still store MEK so other commands work
        session.store_mek(mek.as_bytes()).ok();
        println!("{} Vault unlocked (no vaults found).", "✓".green());
    }
}
