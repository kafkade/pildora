import XCTest
@testable import PildoraNotificationScheduler

/// Deterministic stand-in for the acceptance criterion:
/// "Stress test: verify 20+ medication schedules deliver correctly over 48 hours."
///
/// Physical-device delivery testing remains blocked by Apple Developer
/// enrollment (issue #25). This simulation validates the rotation invariants the
/// device test would ultimately confirm: the pending queue never overflows the
/// 64-notification limit, and — with replenishment on every user action — every
/// dose within the 48-hour window is delivered exactly once, on time, in
/// chronological order.
final class StressTest48hTests: XCTestCase {

    func testTwentyPlusMedicationsDeliverCorrectlyOver48Hours() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)

        let start = Fixture.now
        let windowEnd = start.addingTimeInterval(48 * 3600)

        // 24 medications × 3 doses/day across 3 days (covers the 48h window plus
        // a margin) => 216 candidate doses, far exceeding the 60-slot budget and
        // forcing continuous rotation.
        let allDoses = Fixture.schedules(medications: 24, dosesPerDay: 3, days: 3, base: start)
        XCTAssertGreaterThan(allDoses.count, 60, "Scenario must exceed the budget to exercise rotation")

        // Doses that fall inside the 48h window are the ones that must all be
        // delivered on time.
        let expectedInWindow = allDoses
            .filter { $0.scheduledAt > start && $0.scheduledAt <= windowEnd }
            .sorted()
        XCTAssertGreaterThan(expectedInWindow.count, 60)

        var deliveredIds: Set<String> = []
        var deliveredTimes: [Date] = []
        var virtualNow = start
        var maxPendingObserved = 0
        var iterations = 0
        let iterationCap = expectedInWindow.count + 100

        while virtualNow < windowEnd {
            iterations += 1
            XCTAssertLessThan(iterations, iterationCap, "Simulation failed to make progress")

            // Replenish from all not-yet-delivered future doses (models an app
            // foreground / post-action refresh).
            let remaining = allDoses.filter { !deliveredIds.contains($0.id) }
            let plan = try await scheduler.replenish(candidates: remaining, now: virtualNow)

            // INVARIANT 1: never exceed the budget.
            XCTAssertLessThanOrEqual(plan.scheduled.count, NotificationBudget.default.maxDoseNotifications)
            let pending = await center.pendingDoseNotifications()
            XCTAssertLessThanOrEqual(pending.count, InMemoryNotificationCenter.pendingLimit)
            maxPendingObserved = max(maxPendingObserved, pending.count)

            // The soonest instant the OS would fire at.
            guard let soonest = pending.map(\.fireDate).min(), soonest <= windowEnd else {
                break
            }

            // INVARIANT 2: the soonest pending instant is the soonest undelivered
            // instant overall — nothing imminent was starved by rotation.
            let soonestRemaining = remaining
                .filter { $0.scheduledAt > virtualNow }
                .map(\.scheduledAt)
                .min()
            XCTAssertEqual(soonest, soonestRemaining,
                           "Rotation must always keep the soonest undelivered dose pending")

            // Advance to that instant and deliver *every* dose due then (real
            // notifications co-scheduled to the same minute all fire together).
            virtualNow = soonest
            let dueNow = pending.filter { $0.fireDate == soonest }.sorted { $0.identifier < $1.identifier }
            for planned in dueNow {
                guard let firedDose = allDoses.first(where: { $0.id == planned.identifier }) else {
                    return XCTFail("Delivered a notification with no matching dose")
                }
                deliveredIds.insert(planned.identifier)
                deliveredTimes.append(soonest)
                _ = try await scheduler.handle(
                    action: .taken,
                    for: firedDose,
                    candidates: allDoses.filter { !deliveredIds.contains($0.id) },
                    now: virtualNow
                )
            }
        }

        // Every in-window dose delivered exactly once.
        XCTAssertEqual(deliveredIds.count, deliveredTimes.count, "No dose delivered twice")
        XCTAssertEqual(
            deliveredIds,
            Set(expectedInWindow.map(\.id)),
            "Every dose in the 48h window must be delivered"
        )

        // Delivered in chronological order.
        XCTAssertEqual(deliveredTimes, deliveredTimes.sorted(), "Doses delivered out of order")

        // The queue was genuinely under rotation pressure (near the budget).
        XCTAssertGreaterThan(maxPendingObserved, 50)
        XCTAssertLessThanOrEqual(maxPendingObserved, NotificationBudget.default.maxDoseNotifications)
    }
}
