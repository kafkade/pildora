use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process;

use chrono::Utc;
use colored::Colorize;
use comfy_table::{ContentArrangement, Table};
use uuid::Uuid;

use crate::cli::MedCommands;
use crate::context::UnlockedContext;
use crate::drug_index;
use crate::models::Medication;
use crate::storage::typed::{list_typed_items, store_typed_item};

const ITEM_TYPE: &str = "medication";

pub fn run(cmd: &MedCommands) {
    match cmd {
        MedCommands::Add {
            name,
            dosage,
            form,
            generic,
            brand,
            prescriber,
            pharmacy,
            notes,
            drug_index,
        } => add(
            name,
            dosage.as_deref(),
            form.as_deref(),
            generic.as_deref(),
            brand.as_deref(),
            prescriber.as_deref(),
            pharmacy.as_deref(),
            notes.as_deref(),
            drug_index.as_ref(),
        ),
        MedCommands::List => list(),
        MedCommands::Show { name } => show(name),
        MedCommands::Edit {
            name,
            dosage,
            form,
            notes,
            prescriber,
            pharmacy,
        } => edit(
            name,
            dosage.as_deref(),
            form.as_deref(),
            notes.as_deref(),
            prescriber.as_deref(),
            pharmacy.as_deref(),
        ),
        MedCommands::Delete { name, force } => delete(name, *force),
    }
}

/// Resolve the drug index path: explicit flag > default location > None.
fn resolve_index_path(explicit: Option<&PathBuf>) -> Option<PathBuf> {
    if let Some(p) = explicit {
        if p.exists() {
            return Some(p.clone());
        }
        return None;
    }
    let default = drug_index::default_index_path();
    if default.exists() {
        Some(default)
    } else {
        None
    }
}

/// Determine whether the caller provided enough flags to skip interactive selection.
fn is_non_interactive(generic: Option<&str>, brand: Option<&str>) -> bool {
    generic.is_some() || brand.is_some()
}

#[allow(clippy::too_many_arguments)]
fn add(
    name: &str,
    dosage: Option<&str>,
    form: Option<&str>,
    generic: Option<&str>,
    brand: Option<&str>,
    prescriber: Option<&str>,
    pharmacy: Option<&str>,
    notes: Option<&str>,
    explicit_index: Option<&PathBuf>,
) {
    let ctx = UnlockedContext::require();
    let now = Utc::now();

    // Try autocomplete from the drug index
    let (resolved_generic, resolved_brand, resolved_rxnorm) =
        attempt_autocomplete(name, generic, brand, explicit_index);

    let med = Medication {
        id: Uuid::new_v4(),
        name: name.to_string(),
        generic_name: generic.map(String::from).or(resolved_generic),
        brand_name: brand.map(String::from).or(resolved_brand),
        dosage: dosage.unwrap_or_default().to_string(),
        form: form.unwrap_or_default().to_string(),
        prescriber: prescriber.map(String::from),
        pharmacy: pharmacy.map(String::from),
        notes: notes.map(String::from),
        rxnorm_id: resolved_rxnorm,
        start_date: None,
        end_date: None,
        created_at: now,
        updated_at: now,
    };

    store_typed_item(&ctx.storage, &ctx.vault_key, &ctx.vault_id, ITEM_TYPE, &med).unwrap_or_else(
        |e| {
            eprintln!("{} Failed to store medication: {e}", "\u{2717}".red());
            process::exit(1);
        },
    );

    println!(
        "{} Added medication: {}",
        "\u{2713}".green(),
        med.name.green()
    );

    // Show what was auto-populated
    if let Some(ref g) = med.generic_name {
        println!("  Generic: {g}");
    }
    if let Some(ref b) = med.brand_name {
        println!("  Brand:   {b}");
    }
    if let Some(ref r) = med.rxnorm_id {
        println!("  RxNorm:  {r}");
    }
}

/// Try to match the medication name against the drug index.
///
/// Returns `(generic_name, brand_name, rxnorm_id)` resolved from the index,
/// or `(None, None, None)` when no index is available or the user skips.
fn attempt_autocomplete(
    name: &str,
    generic: Option<&str>,
    brand: Option<&str>,
    explicit_index: Option<&PathBuf>,
) -> (Option<String>, Option<String>, Option<String>) {
    let Some(index_path) = resolve_index_path(explicit_index) else {
        return (None, None, None);
    };

    let matches = drug_index::search_all(&index_path, name, 10);
    if matches.is_empty() {
        return (None, None, None);
    }

    // Non-interactive mode: just note the match count and use the best match
    if is_non_interactive(generic, brand) {
        let best = &matches[0];
        eprintln!(
            "{} Found {} drug index match(es) for \"{name}\"",
            "ℹ".blue(),
            matches.len()
        );
        return (best.generic_name.clone(), None, best.rxcui.clone());
    }

    // Interactive selection
    eprintln!();
    eprintln!("Drug matches for \"{}\":", name.yellow());
    for (i, m) in matches.iter().enumerate() {
        let generic_display = m
            .generic_name
            .as_deref()
            .map_or(String::new(), |g| format!(", generic: {g}"));
        eprintln!(
            "  {}. {} (type: {}{})",
            i + 1,
            m.preferred_name.bold(),
            m.product_type,
            generic_display,
        );
    }
    eprintln!();
    eprint!(
        "Select [1-{}] or press Enter for manual entry: ",
        matches.len()
    );
    io::stderr().flush().ok();

    let mut input = String::new();
    if io::stdin().lock().read_line(&mut input).is_err() {
        return (None, None, None);
    }

    let selection: usize = match input.trim().parse() {
        Ok(n) if n >= 1 && n <= matches.len() => n,
        _ => return (None, None, None),
    };

    let chosen = &matches[selection - 1];

    // Look up brand names from aliases
    let brand_names = drug_index::get_brand_names(&index_path, &chosen.preferred_name);
    let brand_name = brand_names.into_iter().next();

    (
        chosen.generic_name.clone(),
        brand_name,
        chosen.rxcui.clone(),
    )
}

fn list() {
    let ctx = UnlockedContext::require();

    let meds: Vec<(String, Medication)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, ITEM_TYPE).unwrap_or_else(
            |e| {
                eprintln!("{} Failed to list medications: {e}", "\u{2717}".red());
                process::exit(1);
            },
        );

    if meds.is_empty() {
        println!("No medications found. Use 'pildora med add' to add one.");
        return;
    }

    let mut table = Table::new();
    table.set_content_arrangement(ContentArrangement::Dynamic);
    table.set_header(vec!["#", "Name", "Dosage", "Form", "Notes"]);

    for (i, (_id, med)) in meds.iter().enumerate() {
        table.add_row(vec![
            (i + 1).to_string(),
            med.name.clone(),
            med.dosage.clone(),
            med.form.clone(),
            med.notes.clone().unwrap_or_default(),
        ]);
    }

    println!("{table}");
}

fn show(query: &str) {
    let ctx = UnlockedContext::require();
    let (_item_id, med) = ctx.find_medication(query);

    println!("{:<13}{}", "Name:".bold(), med.name);
    if let Some(ref g) = med.generic_name {
        println!("{:<13}{g}", "Generic:");
    }
    if let Some(ref b) = med.brand_name {
        println!("{:<13}{b}", "Brand:");
    }
    if !med.dosage.is_empty() {
        println!("{:<13}{}", "Dosage:", med.dosage);
    }
    if !med.form.is_empty() {
        println!("{:<13}{}", "Form:", med.form);
    }
    if let Some(ref p) = med.prescriber {
        println!("{:<13}{p}", "Prescriber:");
    }
    if let Some(ref ph) = med.pharmacy {
        println!("{:<13}{ph}", "Pharmacy:");
    }
    if let Some(ref n) = med.notes {
        println!("{:<13}{n}", "Notes:");
    }
    if let Some(ref r) = med.rxnorm_id {
        println!("{:<13}{r}", "RxNorm ID:");
    }
    if let Some(ref s) = med.start_date {
        println!("{:<13}{s}", "Start date:");
    }
    if let Some(ref e) = med.end_date {
        println!("{:<13}{e}", "End date:");
    }
    println!("{:<13}{}", "Created:", med.created_at);
    println!("{:<13}{}", "Updated:", med.updated_at);
}

fn edit(
    query: &str,
    dosage: Option<&str>,
    form: Option<&str>,
    notes: Option<&str>,
    prescriber: Option<&str>,
    pharmacy: Option<&str>,
) {
    if dosage.is_none()
        && form.is_none()
        && notes.is_none()
        && prescriber.is_none()
        && pharmacy.is_none()
    {
        eprintln!(
            "No fields to update. Use --dosage, --form, --notes, --prescriber, or --pharmacy."
        );
        process::exit(1);
    }

    let ctx = UnlockedContext::require();
    let (item_id, mut med) = ctx.find_medication(query);

    let mut changed = Vec::new();

    if let Some(d) = dosage {
        d.clone_into(&mut med.dosage);
        changed.push("dosage");
    }
    if let Some(f) = form {
        f.clone_into(&mut med.form);
        changed.push("form");
    }
    if let Some(n) = notes {
        med.notes = Some(n.to_string());
        changed.push("notes");
    }
    if let Some(p) = prescriber {
        med.prescriber = Some(p.to_string());
        changed.push("prescriber");
    }
    if let Some(ph) = pharmacy {
        med.pharmacy = Some(ph.to_string());
        changed.push("pharmacy");
    }

    med.updated_at = Utc::now();

    let blob = pildora_crypto::vault::encrypt_json(&med, &ctx.vault_key).unwrap_or_else(|e| {
        eprintln!("{} Encryption failed: {e}", "\u{2717}".red());
        process::exit(1);
    });

    ctx.storage
        .update_item(&item_id, blob.to_bytes())
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to update medication: {e}", "\u{2717}".red());
            process::exit(1);
        });

    println!(
        "{} Updated {}: {}",
        "\u{2713}".green(),
        med.name.green(),
        changed.join(", ")
    );
}

fn delete(query: &str, force: bool) {
    let ctx = UnlockedContext::require();
    let (item_id, med) = ctx.find_medication(query);

    if !force {
        print!("Delete '{}'? [y/N]: ", med.name);
        io::stdout().flush().ok();
        let mut line = String::new();
        io::stdin().lock().read_line(&mut line).unwrap_or_else(|e| {
            eprintln!("{} Failed to read input: {e}", "\u{2717}".red());
            process::exit(1);
        });
        if !line.trim().eq_ignore_ascii_case("y") {
            println!("Cancelled.");
            return;
        }
    }

    ctx.storage.delete_item(&item_id).unwrap_or_else(|e| {
        eprintln!("{} Failed to delete medication: {e}", "\u{2717}".red());
        process::exit(1);
    });

    println!(
        "{} Deleted medication: {}",
        "\u{2713}".green(),
        med.name.green()
    );
}
