use std::path::PathBuf;
use std::{fs, process};

use chrono::Utc;
use colored::Colorize;

use crate::context::UnlockedContext;
use crate::export::{self, ExportData, ExportMetadata};
use crate::models::{DoseLog, Medication, Schedule, VaultMetadata};
use crate::storage::typed::list_typed_items;

/// Try to read the vault name from encrypted metadata.
fn load_vault_name(ctx: &UnlockedContext) -> String {
    ctx.storage
        .get_vault_metadata(&ctx.vault_id)
        .ok()
        .and_then(|blob_bytes| {
            let blob = pildora_crypto::vault::EncryptedBlob::from_bytes(blob_bytes).ok()?;
            let meta: VaultMetadata =
                pildora_crypto::vault::decrypt_json(&blob, &ctx.vault_key).ok()?;
            Some(meta.name)
        })
        .unwrap_or_else(|| "My Meds".to_string())
}

pub fn run(format: &str, output: Option<PathBuf>) {
    let ctx = UnlockedContext::require();

    let medications: Vec<(String, Medication)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, "medication").unwrap_or_else(
            |e| {
                eprintln!("Failed to load medications: {e}");
                process::exit(1);
            },
        );
    let schedules: Vec<(String, Schedule)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, "schedule").unwrap_or_else(
            |e| {
                eprintln!("Failed to load schedules: {e}");
                process::exit(1);
            },
        );
    let dose_logs: Vec<(String, DoseLog)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, "dose_log").unwrap_or_else(
            |e| {
                eprintln!("Failed to load dose logs: {e}");
                process::exit(1);
            },
        );

    let vault_name = load_vault_name(&ctx);

    let data = ExportData {
        metadata: ExportMetadata {
            export_date: Utc::now().to_rfc3339(),
            vault_name,
            pildora_version: env!("CARGO_PKG_VERSION").to_string(),
            medication_count: medications.len(),
            schedule_count: schedules.len(),
            dose_log_count: dose_logs.len(),
        },
        medications: medications.into_iter().map(|(_, m)| m).collect(),
        schedules: schedules.into_iter().map(|(_, s)| s).collect(),
        dose_logs: dose_logs.into_iter().map(|(_, d)| d).collect(),
    };

    let content = match format {
        "json" => export::to_json(&data).unwrap_or_else(|e| {
            eprintln!("Failed to serialize JSON: {e}");
            process::exit(1);
        }),
        "csv" => {
            let meds_csv = export::medications_to_csv(&data.medications).unwrap_or_else(|e| {
                eprintln!("Failed to generate medications CSV: {e}");
                process::exit(1);
            });
            let logs_csv = export::dose_logs_to_csv(&data.dose_logs).unwrap_or_else(|e| {
                eprintln!("Failed to generate dose logs CSV: {e}");
                process::exit(1);
            });
            format!("# Medications\n{meds_csv}\n# Dose Logs\n{logs_csv}")
        }
        _ => {
            eprintln!("Unknown format: {format}. Use 'json' or 'csv'.");
            process::exit(1);
        }
    };

    match output {
        Some(path) => {
            fs::write(&path, &content).unwrap_or_else(|e| {
                eprintln!("Failed to write to {}: {e}", path.display());
                process::exit(1);
            });
            println!("{} Exported to {}", "✓".green(), path.display());
        }
        None => print!("{content}"),
    }
}
