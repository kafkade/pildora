mod cli;
mod commands;
mod context;
mod models;
pub mod schedule_engine;
mod session;
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
        Commands::Med(cmd) => commands::med::run(&cmd),
        Commands::Dose(ref cmd) => commands::dose::run(cmd),
        Commands::Schedule(ref cmd) => commands::schedule::run(cmd),
        Commands::Export { output } => commands::export::run(output),
        Commands::RecoveryKey { regenerate } => commands::recovery::run(regenerate),
        Commands::Completions { shell } => commands::completions::run(shell),
    }
}
