import Foundation

// MARK: - DoseActionResult

/// The outcome of handling a notification action, returned to the app so it can
/// persist the corresponding dose-log entry. This package deliberately does not
/// own the encrypted dose log.
public struct DoseActionResult: Equatable, Sendable {
    /// The dose the user acted on.
    public var dose: DoseNotification
    /// The action the user took.
    public var action: DoseNotificationAction
    /// When the action was handled.
    public var handledAt: Date
    /// For a snooze, the instant the re-reminder will fire. `nil` otherwise.
    public var snoozedUntil: Date?

    public init(
        dose: DoseNotification,
        action: DoseNotificationAction,
        handledAt: Date,
        snoozedUntil: Date? = nil
    ) {
        self.dose = dose
        self.action = action
        self.handledAt = handledAt
        self.snoozedUntil = snoozedUntil
    }
}

// MARK: - NotificationScheduler

/// The top-level entry point that wires the planner, content builder, overdue
/// tracker, and permission wrapper onto a ``NotificationScheduling`` center.
///
/// Everything here is **local-only**: no server is ever contacted, and content
/// is computed on-device from local encrypted data. This preserves the
/// zero-knowledge guarantee — the server never learns a user's dose schedule.
///
/// Typical lifecycle:
/// 1. `registerCategories()` and `requestAuthorization()` during onboarding.
/// 2. `replenish(candidates:)` on launch, after medication CRUD, and after each
///    action, passing the next upcoming doses from the schedule engine.
/// 3. `handle(action:for:candidates:)` from the notification-center delegate.
/// 4. `refreshOverdue(unresolvedDoses:)` on launch/foreground.
public struct NotificationScheduler: Sendable {

    /// Identifier prefix for one-shot snooze re-reminders. Distinct from the
    /// dose prefix so rotation's "remove all dose notifications" step never
    /// clears a pending snooze; snoozes draw from the reserved slot pool.
    public static let snoozeIdentifierPrefix = "snooze-"

    /// Fixed identifier for the single overdue summary notification.
    public static let overdueSummaryIdentifier = "overdue-summary"

    private let center: NotificationScheduling
    private let planner: NotificationPlanner
    private let contentBuilder: DoseNotificationContentBuilder
    private let overdueTracker: OverdueTracker
    private let snoozeOption: SnoozeOption

    public init(
        center: NotificationScheduling,
        budget: NotificationBudget = .default,
        overdueGracePeriod: TimeInterval = 30 * 60,
        snooze: SnoozeOption = .default
    ) {
        self.center = center
        self.planner = NotificationPlanner(budget: budget)
        self.contentBuilder = DoseNotificationContentBuilder()
        self.overdueTracker = OverdueTracker(gracePeriod: overdueGracePeriod)
        self.snoozeOption = snooze
    }

    // MARK: Onboarding

    /// Registers the dose-reminder + overdue categories with the system.
    public func registerCategories() async {
        await center.setCategories(DoseNotificationCategories.all(snooze: snoozeOption))
    }

    /// Requests notification authorization, prompting only when undetermined.
    @discardableResult
    public func requestAuthorization() async throws -> NotificationAuthorization.Outcome {
        try await NotificationAuthorization(center: center).requestIfNeeded()
    }

    /// The current authorization status.
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    // MARK: Rotation

    /// Replaces the pending dose notifications with the highest-priority,
    /// soonest doses that fit the budget.
    ///
    /// Uses a remove-all-then-add rotation so the pending set is always a clean
    /// reflection of the plan and the 65th-notification silent-drop can never
    /// occur. Pending snoozes and the overdue summary are preserved (they do not
    /// carry the dose identifier prefix).
    @discardableResult
    public func replenish(
        candidates: [DoseNotification],
        now: Date = Date()
    ) async throws -> NotificationPlan {
        let pending = await center.pendingIdentifiers()
        let doseIdentifiers = pending.filter {
            $0.hasPrefix(DoseNotification.identifierPrefix)
        }
        await center.removePending(identifiers: doseIdentifiers)

        let plan = planner.plan(candidates: candidates, now: now)
        for dose in plan.scheduled {
            try await center.add(contentBuilder.plannedNotification(for: dose))
        }
        return plan
    }

    // MARK: Actions

    /// Applies a notification action, returning the result the app should log.
    ///
    /// - Taken / Skip: clears any pending reminder or snooze for the dose (the
    ///   original already fired) so it cannot re-alert.
    /// - Snooze: schedules a one-shot re-reminder at `now + minutes`.
    public func apply(
        action: DoseNotificationAction,
        to dose: DoseNotification,
        now: Date = Date()
    ) async throws -> DoseActionResult {
        // Always clear the dose's original reminder and any prior snooze.
        await center.removePending(identifiers: [dose.id, snoozeIdentifier(for: dose)])

        switch action {
        case .taken, .skip:
            return DoseActionResult(dose: dose, action: action, handledAt: now)

        case let .snooze(minutes):
            let clamped = max(1, minutes)
            let fireDate = now.addingTimeInterval(TimeInterval(clamped * 60))
            let planned = PlannedNotification(
                identifier: snoozeIdentifier(for: dose),
                content: contentBuilder.content(for: dose),
                fireDate: fireDate
            )
            try await center.add(planned)
            return DoseActionResult(
                dose: dose,
                action: action,
                handledAt: now,
                snoozedUntil: fireDate
            )
        }
    }

    /// Applies an action and then replenishes the rotation so a freed slot is
    /// immediately backfilled — the "replenish after each action" behavior.
    @discardableResult
    public func handle(
        action: DoseNotificationAction,
        for dose: DoseNotification,
        candidates: [DoseNotification],
        now: Date = Date()
    ) async throws -> DoseActionResult {
        let result = try await apply(action: action, to: dose, now: now)
        _ = try await replenish(candidates: candidates, now: now)
        return result
    }

    // MARK: Overdue

    /// Updates the app-icon badge and overdue summary from unresolved past
    /// doses. Posts a single summary when doses are missed and clears it (and
    /// the badge) when none remain.
    @discardableResult
    public func refreshOverdue(
        unresolvedDoses: [DoseNotification],
        now: Date = Date()
    ) async throws -> OverdueStatus {
        let status = overdueTracker.evaluate(unresolvedDoses: unresolvedDoses, now: now)
        await center.setBadgeCount(status.badgeCount)

        if status.shouldPostSummary {
            let planned = PlannedNotification(
                identifier: Self.overdueSummaryIdentifier,
                content: contentBuilder.overdueSummaryContent(missedCount: status.badgeCount),
                // Fire almost immediately; a calendar trigger needs a future
                // instant, so nudge a few seconds ahead of `now`.
                fireDate: now.addingTimeInterval(5)
            )
            try await center.add(planned)
        } else {
            await center.removePending(identifiers: [Self.overdueSummaryIdentifier])
        }
        return status
    }

    // MARK: Helpers

    private func snoozeIdentifier(for dose: DoseNotification) -> String {
        "\(Self.snoozeIdentifierPrefix)\(dose.scheduleId)-\(Int(dose.scheduledAt.timeIntervalSince1970))"
    }
}
