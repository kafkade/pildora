import Foundation

// MARK: - ScheduleRule

/// The engine's input: everything needed to compute when a medication's doses
/// occur. It intentionally mirrors — but does not depend on — the persisted
/// `Schedule` record, so the engine stays a pure, dependency-free computation
/// layer. A future persistence-wiring issue maps stored rows onto this type.
///
/// All identifiers are carried through onto every `DoseOccurrence` so callers
/// (notification scheduler, Today view, adherence) can associate a computed
/// dose back to its medication/schedule/vault without a lookup.
public struct ScheduleRule: Hashable, Sendable {
    /// The originating schedule's identifier.
    public var scheduleId: String
    public var medicationId: String
    public var vaultId: String
    public var pattern: SchedulePattern
    /// The first day the schedule is active (its date component anchors
    /// `everyNDays` and `cycling` cycle math). Times-of-day on this value are
    /// ignored for cycle counting.
    public var startDate: Date
    /// The last day the schedule is active, inclusive of that day's doses.
    /// `nil` means open-ended.
    public var endDate: Date?
    /// Resolves `DoseTimeWindow` anchors to concrete times.
    public var windowConfiguration: TimeWindowConfiguration

    public init(
        scheduleId: String,
        medicationId: String,
        vaultId: String,
        pattern: SchedulePattern,
        startDate: Date,
        endDate: Date? = nil,
        windowConfiguration: TimeWindowConfiguration = .default
    ) {
        self.scheduleId = scheduleId
        self.medicationId = medicationId
        self.vaultId = vaultId
        self.pattern = pattern
        self.startDate = startDate
        self.endDate = endDate
        self.windowConfiguration = windowConfiguration
    }
}
