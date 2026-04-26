use colored::Colorize;

use crate::session::Session;

pub fn run() {
    let data_dir = crate::storage::default_data_dir();
    let session = Session::new(&data_dir);
    session.clear().ok();
    println!("{} Vault locked. Session cleared.", "✓".green());
}
