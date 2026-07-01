import Foundation

// Storage-facing enumerations shared across the data model. Each is a
// `String`-backed `RawRepresentable`, so GRDB persists it as a TEXT column
// (via the record's `Codable` conformance) and unknown legacy values decode
// through the explicit failable inits below rather than throwing.

// MARK: - VaultProfileType

/// The kind of person or entity a vault tracks. Presented to users as a
/// "profile"; the word "vault" is reserved for security/settings contexts.
public enum VaultProfileType: String, Codable, CaseIterable, Sendable {
    case personal
    case child
    case dependent
    case pet
    case other
}

// MARK: - MedicationForm

/// The physical form a medication or supplement takes.
public enum MedicationForm: String, Codable, CaseIterable, Sendable {
    case tablet
    case capsule
    case liquid
    case injection
    case patch
    case drops
    case gummy
    case powder
    case other
}

// MARK: - MedicationCategory

/// Grouping bucket used to organize the medication list. "Meds" always covers
/// both medications and supplements/vitamins.
public enum MedicationCategory: String, Codable, CaseIterable, Sendable {
    case prescription
    case overTheCounter
    case supplement
    case vitamin
}

// MARK: - SchedulePattern

/// How doses recur over time. Pattern-specific fields on `Schedule`
/// (`daysJson`, `intervalDays`) are interpreted according to this value.
public enum SchedulePattern: String, Codable, CaseIterable, Sendable {
    /// One or more fixed times every day.
    case daily
    /// Fixed times, but only on specific weekdays (see `daysJson`).
    case specificDays = "specific_days"
    /// Every N days starting from `startDate` (see `intervalDays`).
    case everyNDays = "every_n_days"
    /// As-needed; no scheduled times.
    case asNeeded = "prn"
}

// MARK: - DoseStatus

/// The outcome recorded for a scheduled or as-needed dose.
public enum DoseStatus: String, Codable, CaseIterable, Sendable {
    case taken
    case skipped
    case missed
    case snoozed
}
