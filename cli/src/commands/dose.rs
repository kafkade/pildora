use std::fmt::Write;
use std::process;

use chrono::{DateTime, Local, NaiveTime, TimeZone, Utc};
use colored::Colorize;
use comfy_table::{ContentArrangement, Table};

use crate::cli::DoseCommands;
use crate::context::UnlockedContext;
use crate::models::{DoseLog, DoseStatus, Schedule};
use crate::schedule_engine::doses_for_date;
use crate::storage::typed::{list_typed_items, store_typed_item};

const DOSE_ITEM_TYPE: &str = "dose_log";
const SCHEDULE_ITEM_TYPE: &str = "schedule";

pub fn run(cmd: &DoseCommands) {
    match cmd {
        DoseCommands::Log {
            medication,
            at,
            notes,
        } => log_dose(medication, at.as_deref(), notes.as_deref()),
        DoseCommands::Skip { medication, reason } => skip(medication, reason.as_deref()),
        DoseCommands::Today => today(),
        DoseCommands::History { medication, days } => history(medication.as_deref(), *days),
    }
}

fn log_dose(med_query: &str, at_str: Option<&str>, notes: Option<&str>) {
    let ctx = UnlockedContext::require();
    let (_med_item_id, med) = ctx.find_medication(med_query);

    let taken_at = parse_dose_time(at_str);
    let now = Utc::now();

    let dose_log = DoseLog {
        medication_id: med.id.to_string(),
        medication_name: med.name.clone(),
        taken_at,
        status: DoseStatus::Taken,
        notes: notes.map(String::from),
        created_at: now,
    };

    store_typed_item(
        &ctx.storage,
        &ctx.vault_key,
        &ctx.vault_id,
        DOSE_ITEM_TYPE,
        &dose_log,
    )
    .unwrap_or_else(|e| {
        eprintln!("{} Failed to store dose log: {e}", "\u{2717}".red());
        process::exit(1);
    });

    let local_time = taken_at.with_timezone(&Local);
    println!(
        "{} Logged dose of {} at {}",
        "\u{2713}".green(),
        med.name.green(),
        local_time.format("%H:%M")
    );
}

fn skip(med_query: &str, reason: Option<&str>) {
    let ctx = UnlockedContext::require();
    let (_med_item_id, med) = ctx.find_medication(med_query);

    let now = Utc::now();

    let dose_log = DoseLog {
        medication_id: med.id.to_string(),
        medication_name: med.name.clone(),
        taken_at: now,
        status: DoseStatus::Skipped,
        notes: reason.map(String::from),
        created_at: now,
    };

    store_typed_item(
        &ctx.storage,
        &ctx.vault_key,
        &ctx.vault_id,
        DOSE_ITEM_TYPE,
        &dose_log,
    )
    .unwrap_or_else(|e| {
        eprintln!("{} Failed to store dose log: {e}", "\u{2717}".red());
        process::exit(1);
    });

    let msg = if let Some(r) = reason {
        format!(
            "\u{23ed} Skipped dose of {} \u{2014} \"{}\"",
            med.name.green(),
            r
        )
    } else {
        format!("\u{23ed} Skipped dose of {}", med.name.green())
    };
    println!("{msg}");
}

fn today() {
    let ctx = UnlockedContext::require();
    let today = Local::now().date_naive();
    let now = Utc::now();

    // Load all schedules
    let schedules: Vec<(String, Schedule)> = list_typed_items(
        &ctx.storage,
        &ctx.vault_key,
        &ctx.vault_id,
        SCHEDULE_ITEM_TYPE,
    )
    .unwrap_or_else(|e| {
        eprintln!("{} Failed to list schedules: {e}", "\u{2717}".red());
        process::exit(1);
    });

    // Load all dose logs
    let all_logs: Vec<(String, DoseLog)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, DOSE_ITEM_TYPE)
            .unwrap_or_else(|e| {
                eprintln!("{} Failed to list dose logs: {e}", "\u{2717}".red());
                process::exit(1);
            });

    // Filter logs to today
    let today_logs: Vec<&DoseLog> = all_logs
        .iter()
        .filter(|(_id, log)| log.taken_at.with_timezone(&Local).date_naive() == today)
        .map(|(_id, log)| log)
        .collect();

    // Compute all scheduled doses for today
    let mut rows: Vec<TodayRow> = Vec::new();

    for (_id, schedule) in &schedules {
        let scheduled_doses = doses_for_date(schedule, today);

        // Load the medication to get dosage info
        let meds: Vec<(String, crate::models::Medication)> =
            list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, "medication")
                .unwrap_or_default();

        let dosage = meds
            .iter()
            .find(|(_id, m)| m.id.to_string() == schedule.medication_id)
            .map(|(_id, m)| m.dosage.clone())
            .unwrap_or_default();

        for dose in &scheduled_doses {
            // Check if there's a log for this med today
            let matching_log = today_logs
                .iter()
                .find(|log| log.medication_id == dose.medication_id);

            let status = match matching_log {
                Some(log) if log.status == DoseStatus::Taken => "\u{2705} Taken".to_string(),
                Some(log) if log.status == DoseStatus::Skipped => "\u{23ed} Skipped".to_string(),
                _ => {
                    if dose.time < now {
                        "\u{274c} Missed".to_string()
                    } else {
                        "\u{23f0} Upcoming".to_string()
                    }
                }
            };

            let local_time = dose.time.with_timezone(&Local);
            rows.push(TodayRow {
                time: local_time,
                medication: dose.medication_name.clone(),
                dosage: dosage.clone(),
                status,
            });
        }
    }

    if rows.is_empty() {
        println!("No doses scheduled for today.");
        return;
    }

    rows.sort_by_key(|r| r.time);

    println!(
        "{}",
        format!("Today's Doses ({})", today.format("%Y-%m-%d")).bold()
    );

    let mut table = Table::new();
    table.set_content_arrangement(ContentArrangement::Dynamic);
    table.set_header(vec!["Time", "Medication", "Dosage", "Status"]);

    for row in &rows {
        table.add_row(vec![
            row.time.format("%H:%M").to_string(),
            row.medication.clone(),
            row.dosage.clone(),
            row.status.clone(),
        ]);
    }

    println!("{table}");
}

struct TodayRow {
    time: DateTime<Local>,
    medication: String,
    dosage: String,
    status: String,
}

fn history(med_query: Option<&str>, days: u32) {
    let ctx = UnlockedContext::require();
    let now_local = Local::now();
    let cutoff_date = now_local.date_naive() - chrono::Duration::days(i64::from(days));

    // Load all dose logs
    let all_logs: Vec<(String, DoseLog)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, DOSE_ITEM_TYPE)
            .unwrap_or_else(|e| {
                eprintln!("{} Failed to list dose logs: {e}", "\u{2717}".red());
                process::exit(1);
            });

    // Filter by date range and optionally by medication
    let med_filter = med_query.map(|q| {
        let (_id, med) = ctx.find_medication(q);
        med.id.to_string()
    });

    let mut filtered: Vec<&DoseLog> = all_logs
        .iter()
        .filter(|(_id, log)| {
            let log_date = log.taken_at.with_timezone(&Local).date_naive();
            if log_date < cutoff_date {
                return false;
            }
            if let Some(ref med_id) = med_filter {
                return &log.medication_id == med_id;
            }
            true
        })
        .map(|(_id, log)| log)
        .collect();

    if filtered.is_empty() {
        println!("No dose history found for the past {days} day(s).");
        return;
    }

    // Sort by taken_at descending
    filtered.sort_by_key(|l| std::cmp::Reverse(l.taken_at));

    // Group by date
    let mut current_date = None;
    for log in &filtered {
        let log_local = log.taken_at.with_timezone(&Local);
        let date = log_local.date_naive();

        if current_date != Some(date) {
            if current_date.is_some() {
                println!();
            }
            println!("{}", date.format("%Y-%m-%d").to_string().bold());
            current_date = Some(date);
        }

        let status_icon = match log.status {
            DoseStatus::Taken => "\u{2705}",
            DoseStatus::Skipped => "\u{23ed}",
        };
        let status_label = match log.status {
            DoseStatus::Taken => "Taken",
            DoseStatus::Skipped => "Skipped",
        };

        let mut line = format!(
            "  {}  {}  {} {}",
            log_local.format("%H:%M"),
            log.medication_name,
            status_icon,
            status_label
        );

        if let Some(ref notes) = log.notes {
            let _ = write!(line, " \u{2014} \"{notes}\"");
        }

        println!("{line}");
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn parse_dose_time(at_str: Option<&str>) -> DateTime<Utc> {
    let Some(raw) = at_str else {
        return Utc::now();
    };

    let time = NaiveTime::parse_from_str(raw, "%H:%M").unwrap_or_else(|_| {
        eprintln!("Invalid time '{raw}'. Use HH:MM format (e.g. 08:00).");
        process::exit(1);
    });

    let today = Local::now().date_naive();
    let local_dt = today.and_time(time);

    Local
        .from_local_datetime(&local_dt)
        .single()
        .unwrap_or_else(|| {
            eprintln!("Ambiguous local time '{raw}'.");
            process::exit(1);
        })
        .with_timezone(&Utc)
}
