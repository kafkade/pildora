use std::process;

use colored::Colorize;
use pildora_crypto::key_hierarchy::{self, MasterEncryptionKey, RecoveryKey};
use pildora_crypto::primitives;

use crate::session::Session;
use crate::storage::Storage;

pub fn run(regenerate: bool) {
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

    // Must be unlocked
    let session = Session::new(&data_dir);
    let mek_bytes = session
        .load_mek()
        .unwrap_or_else(|e| {
            eprintln!("{} Session error: {e}", "✗".red());
            process::exit(1);
        })
        .unwrap_or_else(|| {
            eprintln!("Vault is locked. Run 'pildora unlock' first.");
            process::exit(1);
        });

    if mek_bytes.len() != 32 {
        eprintln!("{} Invalid session data.", "✗".red());
        process::exit(1);
    }
    let mut mek_arr = [0u8; 32];
    mek_arr.copy_from_slice(&mek_bytes);
    let mek = MasterEncryptionKey::from_bytes(mek_arr);

    if regenerate {
        run_regenerate(&store, &mek);
    } else {
        run_display(&account, &mek);
    }
}

fn run_display(account: &crate::storage::AccountState, mek: &MasterEncryptionKey) {
    let rk_encrypted = account.recovery_key_encrypted.as_ref().unwrap_or_else(|| {
        eprintln!("{} No recovery key found in storage.", "✗".red());
        process::exit(1);
    });

    let rk_bytes =
        primitives::aes256_gcm_decrypt(mek.as_bytes(), rk_encrypted, b"pildora:v1:recovery-key")
            .unwrap_or_else(|e| {
                eprintln!("{} Failed to decrypt recovery key: {e}", "✗".red());
                process::exit(1);
            });

    if rk_bytes.len() != 32 {
        eprintln!("{} Invalid recovery key data.", "✗".red());
        process::exit(1);
    }
    let mut rk_arr = [0u8; 32];
    rk_arr.copy_from_slice(&rk_bytes);
    let rk = RecoveryKey::from_bytes(rk_arr);

    println!("{}", "Recovery Key:".bold());
    println!("  {}", rk.to_display_string().cyan());
    println!();
    println!("{}", "⚠ SAVE THIS KEY SOMEWHERE SAFE.".yellow().bold());
    println!("  If you forget your master password, this is the only way to recover your data.");
}

fn run_regenerate(store: &Storage, mek: &MasterEncryptionKey) {
    println!(
        "{}",
        "⚠ This will invalidate your current recovery key.".yellow()
    );
    println!("  If you have written it down, destroy the old copy.");
    println!();

    let confirm = rpassword::prompt_password_stderr("Type 'REGENERATE' to confirm: ")
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to read input: {e}", "✗".red());
            process::exit(1);
        });
    if confirm.trim() != "REGENERATE" {
        println!("Aborted.");
        return;
    }

    let rk = key_hierarchy::generate_recovery_key();
    let recovery_wrapped_mek = key_hierarchy::wrap_mek_for_recovery(mek, &rk).unwrap_or_else(|e| {
        eprintln!("{} Recovery key wrapping failed: {e}", "✗".red());
        process::exit(1);
    });

    let rk_encrypted =
        primitives::aes256_gcm_encrypt(mek.as_bytes(), rk.as_bytes(), b"pildora:v1:recovery-key")
            .unwrap_or_else(|e| {
                eprintln!("{} Recovery key encryption failed: {e}", "✗".red());
                process::exit(1);
            });

    store
        .update_recovery(&recovery_wrapped_mek.0, &rk_encrypted)
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to update recovery data: {e}", "✗".red());
            process::exit(1);
        });

    println!("{}", "✓ Recovery key regenerated.".green().bold());
    println!();
    println!("{}", "New Recovery Key:".bold());
    println!("  {}", rk.to_display_string().cyan());
    println!();
    println!("{}", "⚠ SAVE THIS KEY SOMEWHERE SAFE.".yellow().bold());
    println!("  The previous recovery key is now invalid.");
}
