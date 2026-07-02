import Foundation

// MARK: - NotificationPlan

/// The outcome of a planning pass: the dose notifications that fit within the
/// budget (highest priority, then soonest), plus analysis of what was left out.
public struct NotificationPlan: Equatable, Sendable {
    /// Dose notifications selected for scheduling, in priority-then-time order.
    public var scheduled: [DoseNotification]
    /// Doses that did not fit within the budget this pass.
    public var dropped: [DoseNotification]

    public init(scheduled: [DoseNotification], dropped: [DoseNotification]) {
        self.scheduled = scheduled
        self.dropped = dropped
    }

    /// How many candidate doses were considered.
    public var candidateCount: Int { scheduled.count + dropped.count }

    /// The furthest-out instant covered by the scheduled set.
    public var horizon: Date? { scheduled.map(\.scheduledAt).max() }

    /// Hours of forward coverage from `now` (the safety metric surfaced by the
    /// spike — light users get ~10 days, power users ~2.7 days).
    public func coverageHours(from now: Date) -> Double {
        guard let horizon else { return 0 }
        return max(0, horizon.timeIntervalSince(now) / 3600)
    }

    /// Count of scheduled doses per priority tier.
    public var countsByPriority: [DosePriority: Int] {
        var counts: [DosePriority: Int] = [:]
        for dose in scheduled { counts[dose.priority, default: 0] += 1 }
        return counts
    }
}

// MARK: - NotificationPlanner

/// Selects which upcoming doses become pending notifications, honoring the iOS
/// 64-notification ceiling.
///
/// Pure and deterministic — this is the production form of the rotation
/// algorithm validated in the `notification-spike`:
///
/// ```text
/// plan(candidates, now):
///   1. Drop doses already in the past (at/before `now`)
///   2. De-duplicate by notification identifier
///   3. Sort by soonest due time, then priority (critical first) on ties
///   4. Take the first `budget.maxDoseNotifications`
/// ```
///
/// Taking the soonest N guarantees that no imminent dose is starved by a
/// far-future higher-priority one, so continuous replenishment delivers every
/// dose within the coverage horizon on time; the doses that get dropped are the
/// furthest-out ones, which the next replenishment cycle will pick up.
///
/// The orchestrator applies the result with a **remove-all-then-add** rotation,
/// so this planner never needs to reason about what is currently pending.
public struct NotificationPlanner: Sendable {

    public let budget: NotificationBudget

    public init(budget: NotificationBudget = .default) {
        self.budget = budget
    }

    /// Produce a plan from all candidate doses.
    ///
    /// - Parameters:
    ///   - candidates: Every upcoming dose across all medications. May contain
    ///     past doses and duplicates; both are handled.
    ///   - now: The reference instant; doses at or before it are excluded.
    public func plan(candidates: [DoseNotification], now: Date = Date()) -> NotificationPlan {
        // 1 + 2: keep only future doses, de-duplicated by identifier.
        var seen = Set<String>()
        let future = candidates
            .filter { $0.scheduledAt > now }
            .filter { seen.insert($0.id).inserted }

        // 3: soonest first, priority tiebreak on equal instants
        // (DoseNotification.Comparable).
        let ordered = future.sorted()

        // 4: take the top N that fit the budget.
        let limit = budget.maxDoseNotifications
        let scheduled = Array(ordered.prefix(limit))
        let dropped = Array(ordered.dropFirst(limit))

        return NotificationPlan(scheduled: scheduled, dropped: dropped)
    }
}
