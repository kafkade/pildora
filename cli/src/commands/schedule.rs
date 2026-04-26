use std::process;

use chrono::{Local, NaiveDate, NaiveTime, Utc, Weekday};
use colored::Colorize;
use comfy_table::{ContentArrangement, Table};

use crate::cli::ScheduleCommands;
use crate::context::UnlockedContext;
use crate::models::{Schedule, SchedulePattern};
use crate::schedule_engine::{doses_for_date, next_doses};
use crate::storage::typed::{list_typed_items, store_typed_item};

const ITEM_TYPE: &str = "schedule";

pub fn run(cmd: &ScheduleCommands) {
    match cmd {
        ScheduleCommands::Set {
            medication,
            pattern,
            times,
            interval,
            days,
            start_date,
        } => set(
            medication,
            pattern,
            times.as_deref(),
            *interval,
            days.as_deref(),
            start_date.as_deref(),
        ),
        ScheduleCommands::Show { medication } => show(medication.as_deref()),
    }
}

fn set(
    med_query: &str,
    pattern_str: &str,
    times_str: Option<&str>,
    interval: Option<u32>,
    days_str: Option<&str>,
    start_date_str: Option<&str>,
) {
    let ctx = UnlockedContext::require();
    let (_med_item_id, med) = ctx.find_medication(med_query);

    let pattern = parse_pattern(pattern_str, interval, days_str, start_date_str);

    let times = if matches!(pattern, SchedulePattern::Prn) {
        vec![]
    } else {
        let Some(raw) = times_str else {
            eprintln!("Times are required for non-PRN schedules. Use --times \"08:00,20:00\".");
            process::exit(1);
        };
        parse_and_normalize_times(raw)
    };

    let now = Utc::now();

    // Check for existing schedule for this medication
    let existing: Vec<(String, Schedule)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, ITEM_TYPE).unwrap_or_else(
            |e| {
                eprintln!("{} Failed to list schedules: {e}", "\u{2717}".red());
                process::exit(1);
            },
        );

    let existing_item = existing
        .into_iter()
        .find(|(_id, s)| s.medication_id == med.id.to_string());

    let schedule = Schedule {
        medication_id: med.id.to_string(),
        medication_name: med.name.clone(),
        pattern,
        times,
        created_at: existing_item.as_ref().map_or(now, |(_, s)| s.created_at),
        updated_at: now,
    };

    if let Some((item_id, _)) = existing_item {
        // Update existing schedule
        let blob =
            pildora_crypto::vault::encrypt_json(&schedule, &ctx.vault_key).unwrap_or_else(|e| {
                eprintln!("{} Encryption failed: {e}", "\u{2717}".red());
                process::exit(1);
            });
        ctx.storage
            .update_item(&item_id, blob.to_bytes())
            .unwrap_or_else(|e| {
                eprintln!("{} Failed to update schedule: {e}", "\u{2717}".red());
                process::exit(1);
            });
        println!(
            "{} Updated schedule for {}",
            "\u{2713}".green(),
            med.name.green()
        );
    } else {
        store_typed_item(
            &ctx.storage,
            &ctx.vault_key,
            &ctx.vault_id,
            ITEM_TYPE,
            &schedule,
        )
        .unwrap_or_else(|e| {
            eprintln!("{} Failed to store schedule: {e}", "\u{2717}".red());
            process::exit(1);
        });
        println!(
            "{} Set schedule for {}",
            "\u{2713}".green(),
            med.name.green()
        );
    }

    print_pattern_summary(&schedule);

    // Show next 3 upcoming doses
    let upcoming = next_doses(&schedule, Utc::now(), 3);
    if !upcoming.is_empty() {
        println!("\n{}", "Next doses:".bold());
        for dose in &upcoming {
            let local = dose.time.with_timezone(&Local);
            println!("  \u{2022} {}", local.format("%a %Y-%m-%d %H:%M"));
        }
    }
}

fn show(med_query: Option<&str>) {
    let ctx = UnlockedContext::require();

    let schedules: Vec<(String, Schedule)> =
        list_typed_items(&ctx.storage, &ctx.vault_key, &ctx.vault_id, ITEM_TYPE).unwrap_or_else(
            |e| {
                eprintln!("{} Failed to list schedules: {e}", "\u{2717}".red());
                process::exit(1);
            },
        );

    if schedules.is_empty() {
        println!("No schedules found. Use 'pildora schedule set' to create one.");
        return;
    }

    if let Some(query) = med_query {
        let (_med_item_id, med) = ctx.find_medication(query);
        let med_id = med.id.to_string();

        let found = schedules
            .into_iter()
            .find(|(_id, s)| s.medication_id == med_id);

        match found {
            Some((_id, schedule)) => {
                println!("{} {}", "Schedule for".bold(), med.name.bold());
                print_pattern_summary(&schedule);
                print_times(&schedule);

                let upcoming = next_doses(&schedule, Utc::now(), 5);
                if !upcoming.is_empty() {
                    println!("\n{}", "Upcoming doses:".bold());
                    for dose in &upcoming {
                        let local = dose.time.with_timezone(&Local);
                        println!("  \u{2022} {}", local.format("%a %Y-%m-%d %H:%M"));
                    }
                }
            }
            None => {
                println!("No schedule found for '{}'.", med.name);
            }
        }
    } else {
        // Show all schedules in a table
        let today = Local::now().date_naive();

        let mut table = Table::new();
        table.set_content_arrangement(ContentArrangement::Dynamic);
        table.set_header(vec!["Medication", "Pattern", "Times", "Today"]);

        for (_id, schedule) in &schedules {
            let pattern_str = format_pattern(&schedule.pattern);
            let times_str = schedule
                .times
                .iter()
                .map(|t| t.format("%H:%M").to_string())
                .collect::<Vec<_>>()
                .join(", ");

            let today_doses = doses_for_date(schedule, today);
            let today_str = if today_doses.is_empty() {
                "—".to_string()
            } else {
                format!("{} dose(s)", today_doses.len())
            };

            table.add_row(vec![
                schedule.medication_name.clone(),
                pattern_str,
                times_str,
                today_str,
            ]);
        }

        println!("{table}");
    }
}

// ── Parsing helpers ──────────────────────────────────────────────────────────

fn parse_pattern(
    pattern_str: &str,
    interval: Option<u32>,
    days_str: Option<&str>,
    start_date_str: Option<&str>,
) -> SchedulePattern {
    match pattern_str.to_lowercase().as_str() {
        "daily" => SchedulePattern::Daily,
        "every" => {
            let interval = interval.unwrap_or_else(|| {
                eprintln!("Interval is required for 'every' pattern. Use --interval 3.");
                process::exit(1);
            });
            if interval == 0 {
                eprintln!("Interval must be at least 1.");
                process::exit(1);
            }
            let start_date = start_date_str.map_or_else(
                || Local::now().date_naive(),
                |s| {
                    NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap_or_else(|_| {
                        eprintln!("Invalid start date '{s}'. Use YYYY-MM-DD format.");
                        process::exit(1);
                    })
                },
            );
            SchedulePattern::EveryNDays {
                interval,
                start_date,
            }
        }
        "days" => {
            let Some(raw) = days_str else {
                eprintln!("Days are required for 'days' pattern. Use --days \"mon,wed,fri\".");
                process::exit(1);
            };
            let days = parse_weekdays(raw);
            if days.is_empty() {
                eprintln!("No valid days provided. Use day names like mon,tue,wed.");
                process::exit(1);
            }
            SchedulePattern::SpecificDays { days }
        }
        "prn" | "asneeded" | "as-needed" => SchedulePattern::Prn,
        other => {
            eprintln!("Unknown schedule pattern '{other}'. Use: daily, every, days, prn.");
            process::exit(1);
        }
    }
}

fn parse_weekdays(raw: &str) -> Vec<Weekday> {
    let mut days: Vec<Weekday> = raw
        .split(',')
        .filter_map(|s| {
            let s = s.trim().to_lowercase();
            match s.as_str() {
                "mon" | "monday" => Some(Weekday::Mon),
                "tue" | "tuesday" => Some(Weekday::Tue),
                "wed" | "wednesday" => Some(Weekday::Wed),
                "thu" | "thursday" => Some(Weekday::Thu),
                "fri" | "friday" => Some(Weekday::Fri),
                "sat" | "saturday" => Some(Weekday::Sat),
                "sun" | "sunday" => Some(Weekday::Sun),
                _ => {
                    eprintln!("Unknown day '{s}', skipping.");
                    None
                }
            }
        })
        .collect();
    days.sort_by_key(Weekday::num_days_from_monday);
    days.dedup();
    days
}

fn parse_and_normalize_times(raw: &str) -> Vec<NaiveTime> {
    let mut times: Vec<NaiveTime> = raw
        .split(',')
        .map(|s| {
            let s = s.trim();
            NaiveTime::parse_from_str(s, "%H:%M").unwrap_or_else(|_| {
                eprintln!("Invalid time '{s}'. Use HH:MM format (e.g. 08:00).");
                process::exit(1);
            })
        })
        .collect();
    times.sort();
    times.dedup();
    times
}

// ── Display helpers ──────────────────────────────────────────────────────────

fn format_pattern(pattern: &SchedulePattern) -> String {
    match pattern {
        SchedulePattern::Daily => "Daily".to_string(),
        SchedulePattern::EveryNDays {
            interval,
            start_date,
        } => format!("Every {interval} days (from {start_date})"),
        SchedulePattern::SpecificDays { days } => {
            let day_names: Vec<&str> = days
                .iter()
                .map(|d| match d {
                    Weekday::Mon => "Mon",
                    Weekday::Tue => "Tue",
                    Weekday::Wed => "Wed",
                    Weekday::Thu => "Thu",
                    Weekday::Fri => "Fri",
                    Weekday::Sat => "Sat",
                    Weekday::Sun => "Sun",
                })
                .collect();
            day_names.join(", ")
        }
        SchedulePattern::Prn => "As needed (PRN)".to_string(),
    }
}

fn print_pattern_summary(schedule: &Schedule) {
    println!("  Pattern: {}", format_pattern(&schedule.pattern));
}

fn print_times(schedule: &Schedule) {
    if schedule.times.is_empty() {
        println!("  Times:   (as needed)");
    } else {
        let times_str: Vec<String> = schedule
            .times
            .iter()
            .map(|t| t.format("%H:%M").to_string())
            .collect();
        println!("  Times:   {}", times_str.join(", "));
    }
}
