mod cli;
mod commands;
// Models and storage contain types scaffolded for future commands (med, dose,
// schedule, export). Suppress dead-code warnings until those commands ship.
#[allow(dead_code)]
mod models;
mod session;
#[allow(dead_code)]
mod storage;

use clap::Parser;
use cli::{Cli, Commands};

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init => commands::init::run(),
        Commands::Unlock => commands::unlock::run(),
        Commands::Lock => commands::lock::run(),
        Commands::Status => commands::status::run(),
        Commands::Med(ref cmd) => commands::med::run(cmd),
        Commands::Dose(ref cmd) => commands::dose::run(cmd),
        Commands::Schedule(ref cmd) => commands::schedule::run(cmd),
        Commands::Export { output } => commands::export::run(output),
        Commands::RecoveryKey { regenerate } => commands::recovery::run(regenerate),
        Commands::Completions { shell } => commands::completions::run(shell),
    }
}
