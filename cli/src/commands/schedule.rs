use colored::Colorize;

use crate::cli::ScheduleCommands;

pub fn run(cmd: &ScheduleCommands) {
    match cmd {
        ScheduleCommands::Set { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "schedule set".bold()
        ),
        ScheduleCommands::Show { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "schedule show".bold()
        ),
    }
}
