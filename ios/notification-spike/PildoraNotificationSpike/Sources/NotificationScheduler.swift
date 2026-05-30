import Foundation

/// Manages the rolling window of local notifications within the iOS 64-notification limit.
///
/// This is a platform-independent simulation. In production, replace `SimulatedNotificationCenter`
/// with `UNUserNotificationCenter` calls.
struct NotificationScheduler {

    /// iOS hard limit for pending local notifications per app.
    static let iosLimit = 64

    /// Reserve a few slots for non-dose notifications (low inventory, refill reminders).
    static let reservedSlots = 4

    /// Maximum dose notifications to schedule.
    static let maxDoseNotifications = iosLimit - reservedSlots  // 60

    /// The simulated pending notification queue (replaces UNUserNotificationCenter in production).
    private(set) var pendingNotifications: [ScheduledDose] = []

    /// Metrics for analysis.
    private(set) var totalScheduled = 0
    private(set) var totalDropped = 0
    private(set) var totalReplenishments = 0

    // MARK: - Core algorithm

    /// Replenish the notification queue.
    ///
    /// Called on:
    /// 1. App foreground (`applicationDidBecomeActive`)
    /// 2. After a notification action (Taken / Skip / Snooze)
    /// 3. `BGAppRefreshTask` handler (~every 6 hours)
    /// 4. After medication CRUD changes
    ///
    /// Algorithm:
    /// 1. Remove all pending notifications
    /// 2. Compute future dose times for all medications
    /// 3. Sort by priority then time
    /// 4. Take top `maxDoseNotifications` (60)
    /// 5. Schedule them
    mutating func replenish(
        medications: [MedicationSchedule],
        now: Date = Date(),
        daysAhead: Int = 7
    ) -> ReplenishResult {
        totalReplenishments += 1

        // 1. Compute all future doses within the look-ahead window
        let maxPerMed = daysAhead * 3 + 5  // generous upper bound
        var allDoses: [ScheduledDose] = []
        for med in medications {
            let doses = med.nextDoseTimes(after: now, count: maxPerMed)
            allDoses.append(contentsOf: doses)
        }

        // 2. Sort by priority (critical first), then by time (earliest first)
        allDoses.sort()

        // 3. Take the top N
        let scheduled = Array(allDoses.prefix(Self.maxDoseNotifications))
        let dropped = allDoses.count - scheduled.count

        // 4. Replace the pending queue
        pendingNotifications = scheduled
        totalScheduled += scheduled.count
        totalDropped += max(0, dropped)

        // 5. Compute coverage statistics
        let coverage = computeCoverage(scheduled: scheduled, now: now)

        return ReplenishResult(
            scheduled: scheduled.count,
            dropped: max(0, dropped),
            totalCandidates: allDoses.count,
            coverage: coverage,
            oldestNotification: scheduled.last?.scheduledAt,
            newestNotification: scheduled.first?.scheduledAt
        )
    }

    /// Simulate a notification firing (user took/skipped the dose).
    /// Removes it from pending and triggers a replenish.
    mutating func handleNotificationAction(
        notificationId: String,
        medications: [MedicationSchedule],
        now: Date
    ) -> ReplenishResult {
        pendingNotifications.removeAll { $0.notificationId == notificationId }
        return replenish(medications: medications, now: now)
    }

    // MARK: - Coverage analysis

    private func computeCoverage(
        scheduled: [ScheduledDose],
        now: Date
    ) -> CoverageInfo {
        guard let latest = scheduled.last?.scheduledAt else {
            return CoverageInfo(hoursAhead: 0, daysAhead: 0, byPriority: [:])
        }
        let hoursAhead = latest.timeIntervalSince(now) / 3600.0

        var byPriority: [DosePriority: Int] = [:]
        for dose in scheduled {
            byPriority[dose.priority, default: 0] += 1
        }

        return CoverageInfo(
            hoursAhead: hoursAhead,
            daysAhead: hoursAhead / 24.0,
            byPriority: byPriority
        )
    }
}

// MARK: - Result types

struct ReplenishResult: CustomStringConvertible {
    let scheduled: Int
    let dropped: Int
    let totalCandidates: Int
    let coverage: CoverageInfo
    let oldestNotification: Date?
    let newestNotification: Date?

    var description: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d HH:mm"
        let oldest = oldestNotification.map { fmt.string(from: $0) } ?? "none"
        return """
        Scheduled: \(scheduled)/\(totalCandidates) (\(dropped) dropped)
        Coverage: \(String(format: "%.1f", coverage.daysAhead)) days ahead (latest: \(oldest))
        By priority: \(coverage.byPriority.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
        """
    }
}

struct CoverageInfo {
    let hoursAhead: Double
    let daysAhead: Double
    let byPriority: [DosePriority: Int]
}
