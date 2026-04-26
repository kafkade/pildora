use chrono::{DateTime, NaiveDate, NaiveTime, Utc, Weekday};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A medication or supplement tracked by the user.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Medication {
    pub id: Uuid,
    pub name: String,
    pub generic_name: Option<String>,
    pub brand_name: Option<String>,
    pub dosage: String,
    pub form: String,
    pub prescriber: Option<String>,
    pub pharmacy: Option<String>,
    pub notes: Option<String>,
    pub rxnorm_id: Option<String>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A medication schedule.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Schedule {
    pub medication_id: String,
    pub medication_name: String,
    pub pattern: SchedulePattern,
    pub times: Vec<NaiveTime>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// The recurrence pattern for a schedule.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SchedulePattern {
    /// Every day at the specified times.
    Daily,
    /// Every N days starting from a specific date.
    EveryNDays {
        interval: u32,
        start_date: NaiveDate,
    },
    /// On specific weekdays.
    SpecificDays { days: Vec<Weekday> },
    /// As needed — no fixed schedule.
    Prn,
}

/// A dose log entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoseLog {
    pub medication_id: String,
    pub medication_name: String,
    pub taken_at: DateTime<Utc>,
    pub status: DoseStatus,
    pub notes: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Whether a dose was taken or intentionally skipped.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum DoseStatus {
    Taken,
    Skipped,
}

/// Vault metadata (encrypted under VK).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultMetadata {
    pub name: String,
}
