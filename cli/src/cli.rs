use clap::{Parser, Subcommand};

/// Pildora — Zero-knowledge encrypted medication and supplement tracker
#[derive(Parser)]
#[command(name = "pildora", version, about, long_about = None)]
#[command(propagate_version = true)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Initialize a new vault with a master password
    Init,

    /// Unlock the vault (authenticate with master password)
    Unlock,

    /// Lock the vault (clear session)
    Lock,

    /// Show vault status (locked/unlocked, med count, last activity)
    Status,

    /// Manage medications and supplements
    #[command(subcommand)]
    Med(MedCommands),

    /// Log and view doses
    #[command(subcommand)]
    Dose(DoseCommands),

    /// Manage medication schedules
    #[command(subcommand)]
    Schedule(ScheduleCommands),

    /// Export all data (decrypted JSON)
    Export {
        /// Output file path (defaults to stdout)
        #[arg(short, long)]
        output: Option<std::path::PathBuf>,
    },

    /// Display or regenerate recovery key
    RecoveryKey {
        /// Regenerate the recovery key (requires confirmation)
        #[arg(long)]
        regenerate: bool,
    },

    /// Generate shell completions
    Completions {
        /// Shell to generate completions for
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
}

#[derive(Subcommand)]
pub enum MedCommands {
    /// Add a new medication or supplement
    Add {
        /// Medication name
        name: String,
        /// Dosage (e.g. "10mg")
        #[arg(short, long)]
        dosage: Option<String>,
        /// Dosage form (e.g. tablet, capsule)
        #[arg(short, long)]
        form: Option<String>,
        /// Generic name
        #[arg(long)]
        generic: Option<String>,
        /// Brand name
        #[arg(long)]
        brand: Option<String>,
        /// Prescriber
        #[arg(long)]
        prescriber: Option<String>,
        /// Pharmacy
        #[arg(long)]
        pharmacy: Option<String>,
        /// Notes
        #[arg(short, long)]
        notes: Option<String>,
    },
    /// List all medications
    List,
    /// Show details of a medication
    Show {
        /// Medication name or ID
        name: String,
    },
    /// Edit a medication
    Edit {
        /// Medication name or ID
        name: String,
        /// New dosage
        #[arg(short, long)]
        dosage: Option<String>,
        /// New form
        #[arg(short, long)]
        form: Option<String>,
        /// New notes
        #[arg(short, long)]
        notes: Option<String>,
        /// New prescriber
        #[arg(long)]
        prescriber: Option<String>,
        /// New pharmacy
        #[arg(long)]
        pharmacy: Option<String>,
    },
    /// Delete a medication
    Delete {
        /// Medication name or ID
        name: String,
        /// Skip confirmation prompt
        #[arg(long)]
        force: bool,
    },
}

#[derive(Subcommand)]
pub enum DoseCommands {
    /// Log a dose taken
    Log {
        /// Medication name
        medication: String,
        /// Time taken (HH:MM, defaults to now)
        #[arg(long)]
        at: Option<String>,
        /// Notes
        #[arg(short, long)]
        notes: Option<String>,
    },
    /// Skip a scheduled dose
    Skip {
        /// Medication name
        medication: String,
        /// Reason for skipping
        #[arg(short, long)]
        reason: Option<String>,
    },
    /// Show today's doses
    Today,
    /// Show dose history
    History {
        /// Medication name (omit for all)
        medication: Option<String>,
        /// Number of days to show (default: 7)
        #[arg(short, long, default_value = "7")]
        days: u32,
    },
}

#[derive(Subcommand)]
pub enum ScheduleCommands {
    /// Set a medication schedule
    Set {
        /// Medication name
        medication: String,
        /// Schedule pattern: daily, every, days, prn
        #[arg(short, long, default_value = "daily")]
        pattern: String,
        /// Times (comma-separated, e.g. "08:00,20:00"). Not needed for PRN.
        #[arg(short, long)]
        times: Option<String>,
        /// Interval for 'every' pattern (e.g. 3 for every 3 days)
        #[arg(short, long)]
        interval: Option<u32>,
        /// Days for 'days' pattern (e.g. "mon,wed,fri")
        #[arg(short = 'D', long)]
        days: Option<String>,
        /// Start date for 'every' pattern (YYYY-MM-DD, defaults to today)
        #[arg(long)]
        start_date: Option<String>,
    },
    /// Show the schedule for a medication or all medications
    Show {
        /// Medication name (omit for all)
        medication: Option<String>,
    },
}
