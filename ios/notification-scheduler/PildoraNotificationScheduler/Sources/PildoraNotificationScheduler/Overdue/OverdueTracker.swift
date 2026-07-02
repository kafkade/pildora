import Foundation

// MARK: - OverdueStatus

/// The result of evaluating overdue doses: the badge count to show and, when
/// there are missed doses, the summary notification to post.
public struct OverdueStatus: Equatable, Sendable {
    /// Doses considered overdue (past the grace period, still unresolved).
    public var missedDoses: [DoseNotification]

    public init(missedDoses: [DoseNotification]) {
        self.missedDoses = missedDoses
    }

    /// The app-icon badge count = number of missed doses.
    public var badgeCount: Int { missedDoses.count }

    /// Whether an overdue summary notification should be posted.
    public var shouldPostSummary: Bool { !missedDoses.isEmpty }
}

// MARK: - OverdueTracker

/// Computes the missed-dose badge count and summary from unresolved past doses.
///
/// The package does not own the dose log, so the caller supplies the doses that
/// are (a) scheduled in the past and (b) not yet marked taken/skipped/snoozed.
/// The tracker applies a grace period before counting a dose as overdue, so a
/// dose that just came due is not immediately flagged as missed.
public struct OverdueTracker: Sendable {

    /// How long after a dose's scheduled time before it counts as overdue.
    /// Defaults to 30 minutes, matching the Today view's overdue threshold.
    public let gracePeriod: TimeInterval

    public init(gracePeriod: TimeInterval = 30 * 60) {
        self.gracePeriod = gracePeriod
    }

    /// Evaluate overdue status.
    ///
    /// - Parameters:
    ///   - unresolvedDoses: Doses with no taken/skipped/snoozed outcome yet.
    ///     Future doses and doses still within the grace period are ignored.
    ///   - now: The reference instant.
    public func evaluate(
        unresolvedDoses: [DoseNotification],
        now: Date = Date()
    ) -> OverdueStatus {
        let cutoff = now.addingTimeInterval(-gracePeriod)
        let missed = unresolvedDoses
            .filter { $0.scheduledAt <= cutoff }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        return OverdueStatus(missedDoses: missed)
    }
}
