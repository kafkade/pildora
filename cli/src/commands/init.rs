use std::process;

use colored::Colorize;
use pildora_crypto::{key_hierarchy, primitives, vault};

use crate::models::VaultMetadata;
use crate::session::Session;
use crate::storage::Storage;

pub fn run() {
    let data_dir = crate::storage::default_data_dir();
    let store = Storage::open(&data_dir).unwrap_or_else(|e| {
        eprintln!("{} Failed to open storage: {e}", "✗".red());
        process::exit(1);
    });

    if store.is_initialized().unwrap_or(false) {
        eprintln!("Vault already initialized. Use 'pildora unlock' to access it.");
        process::exit(1);
    }

    let password = prompt_password_with_confirm();
    validate_password(&password);

    // Derive key hierarchy
    let salt = primitives::generate_salt();
    let mk = key_hierarchy::derive_master_key(password.as_bytes(), &salt).unwrap_or_else(|e| {
        eprintln!("{} Key derivation failed: {e}", "✗".red());
        process::exit(1);
    });
    let (_auth, mek) = key_hierarchy::derive_sub_keys(&mk).unwrap_or_else(|e| {
        eprintln!("{} Sub-key derivation failed: {e}", "✗".red());
        process::exit(1);
    });

    // Create default vault
    let vault_id = uuid::Uuid::new_v4().to_string();
    let vk = key_hierarchy::generate_vault_key();
    let wrapped_vk = key_hierarchy::wrap_vault_key(&vk, &mek).unwrap_or_else(|e| {
        eprintln!("{} Key wrapping failed: {e}", "✗".red());
        process::exit(1);
    });

    // Encrypt vault metadata
    let metadata = VaultMetadata {
        name: "My Meds".to_string(),
    };
    let encrypted_meta = vault::encrypt_json(&metadata, &vk).unwrap_or_else(|e| {
        eprintln!("{} Metadata encryption failed: {e}", "✗".red());
        process::exit(1);
    });

    // Generate recovery key and wrap MEK for recovery
    let rk = key_hierarchy::generate_recovery_key();
    let recovery_wrapped_mek =
        key_hierarchy::wrap_mek_for_recovery(&mek, &rk).unwrap_or_else(|e| {
            eprintln!("{} Recovery key wrapping failed: {e}", "✗".red());
            process::exit(1);
        });

    // Encrypt recovery key under MEK so an unlocked user can re-display it
    let rk_encrypted =
        primitives::aes256_gcm_encrypt(mek.as_bytes(), rk.as_bytes(), b"pildora:v1:recovery-key")
            .unwrap_or_else(|e| {
                eprintln!("{} Recovery key encryption failed: {e}", "✗".red());
                process::exit(1);
            });

    // Persist
    store
        .init_account(&salt, &recovery_wrapped_mek.0, &rk_encrypted)
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to initialize account: {e}", "✗".red());
            process::exit(1);
        });
    store
        .create_vault(&vault_id, encrypted_meta.to_bytes(), &wrapped_vk.0)
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to create vault: {e}", "✗".red());
            process::exit(1);
        });

    // Cache MEK in session (best-effort)
    let session = Session::new(&data_dir);
    session.store_mek(mek.as_bytes()).ok();

    // Display success + recovery key
    println!("{}", "✓ Vault initialized successfully!".green().bold());
    println!();
    println!("{}", "Recovery Key:".bold());
    println!("  {}", rk.to_display_string().cyan());
    println!();
    println!("{}", "⚠ SAVE THIS KEY SOMEWHERE SAFE.".yellow().bold());
    println!("  If you forget your master password, this is the only way to recover your data.");
    println!("  Store it on paper in a secure location, NOT on this device.");
}

fn prompt_password_with_confirm() -> String {
    let pass = rpassword::prompt_password_stderr("Master password: ").unwrap_or_else(|e| {
        eprintln!("{} Failed to read password: {e}", "✗".red());
        process::exit(1);
    });
    let confirm = rpassword::prompt_password_stderr("Confirm password: ").unwrap_or_else(|e| {
        eprintln!("{} Failed to read password: {e}", "✗".red());
        process::exit(1);
    });
    if pass != confirm {
        eprintln!("{} Passwords do not match.", "✗".red());
        process::exit(1);
    }
    pass
}

fn validate_password(password: &str) {
    if password.len() < 12 {
        eprintln!("{} Password must be at least 12 characters.", "✗".red());
        eprintln!("  Tip: Use a passphrase like \"correct horse battery staple\".");
        process::exit(1);
    }
}
