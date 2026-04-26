use serde::{Deserialize, Serialize};

/// A medication or supplement tracked by the user.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Medication {
    pub name: String,
    pub dosage: Option<String>,
    pub form: Option<String>,
    pub notes: Option<String>,
}

/// A dose log entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoseLog {
    pub medication_id: String,
    pub taken_at: String,
    pub status: DoseStatus,
    pub notes: Option<String>,
}

/// Whether a dose was taken or intentionally skipped.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DoseStatus {
    Taken,
    Skipped,
}

/// A medication schedule.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Schedule {
    pub medication_id: String,
    pub times: Vec<String>,
    pub days: Option<Vec<String>>,
}

/// Vault metadata (encrypted under VK).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultMetadata {
    pub name: String,
}
