use colored::Colorize;

use crate::cli::MedCommands;

pub fn run(cmd: &MedCommands) {
    match cmd {
        MedCommands::Add { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "med add".bold()
        ),
        MedCommands::List => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "med list".bold()
        ),
        MedCommands::Show { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "med show".bold()
        ),
        MedCommands::Edit { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "med edit".bold()
        ),
        MedCommands::Delete { .. } => println!(
            "{} {} command is not yet implemented.",
            "⚠".yellow(),
            "med delete".bold()
        ),
    }
}
