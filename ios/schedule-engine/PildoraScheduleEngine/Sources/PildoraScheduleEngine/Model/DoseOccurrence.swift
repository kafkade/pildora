import Foundation

// MARK: - DoseOccurrence

/// A single computed dose time produced by the engine. This is the unit the
/// notification scheduler and Today view consume: a concrete instant plus the
/// identifiers and window needed to render and act on it.
public struct DoseOccurrence: Hashable, Sendable {
    public var scheduleId: String
    public var medicationId: String
    public var vaultId: String
    /// The absolute instant the dose is due, resolved in the query's calendar.
    public var scheduledAt: Date
    /// The wall-clock time-of-day the dose was scheduled for (pre-resolution),
    /// preserved for display and de-duplication.
    public var time: TimeOfDay
    /// The part of day this dose belongs to, for Today-view grouping.
    public var window: DoseTimeWindow

    public init(
        scheduleId: String,
        medicationId: String,
        vaultId: String,
        scheduledAt: Date,
        time: TimeOfDay,
        window: DoseTimeWindow
    ) {
        self.scheduleId = scheduleId
        self.medicationId = medicationId
        self.vaultId = vaultId
        self.scheduledAt = scheduledAt
        self.time = time
        self.window = window
    }
}

extension DoseOccurrence: Comparable {
    /// Chronological ordering by due instant, then by identifier for a stable
    /// tie-break when two doses land on the same instant.
    public static func < (lhs: DoseOccurrence, rhs: DoseOccurrence) -> Bool {
        if lhs.scheduledAt != rhs.scheduledAt {
            return lhs.scheduledAt < rhs.scheduledAt
        }
        return lhs.scheduleId < rhs.scheduleId
    }
}
