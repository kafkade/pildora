use colored::Colorize;

use crate::cli::DoseCommands;

pub fn run(cmd: &DoseCommands) {
    match cmd {
        DoseCommands::Log { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "dose log".bold()
        ),
        DoseCommands::Skip { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "dose skip".bold()
        ),
        DoseCommands::Today => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "dose today".bold()
        ),
        DoseCommands::History { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "dose history".bold()
        ),
    }
}
