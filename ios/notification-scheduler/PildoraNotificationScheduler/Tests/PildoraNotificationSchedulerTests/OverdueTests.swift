import XCTest
@testable import PildoraNotificationScheduler

final class OverdueTests: XCTestCase {

    func testCountsOnlyDosesPastGracePeriod() {
        let tracker = OverdueTracker(gracePeriod: 30 * 60)
        let doses = [
            Fixture.dose(schedule: "old", minutesFromNow: -90),   // overdue
            Fixture.dose(schedule: "edge", minutesFromNow: -31),  // overdue
            Fixture.dose(schedule: "grace", minutesFromNow: -20), // within grace
            Fixture.dose(schedule: "future", minutesFromNow: 10), // not due
        ]
        let status = tracker.evaluate(unresolvedDoses: doses, now: Fixture.now)
        XCTAssertEqual(status.badgeCount, 2)
        XCTAssertEqual(status.missedDoses.map(\.scheduleId), ["old", "edge"])
    }

    func testNoMissedDosesMeansNoSummary() {
        let tracker = OverdueTracker()
        let status = tracker.evaluate(
            unresolvedDoses: [Fixture.dose(schedule: "future", minutesFromNow: 10)],
            now: Fixture.now
        )
        XCTAssertFalse(status.shouldPostSummary)
        XCTAssertEqual(status.badgeCount, 0)
    }

    func testRefreshOverduePostsSummaryAndBadge() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let missed = [
            Fixture.dose(schedule: "m1", minutesFromNow: -60),
            Fixture.dose(schedule: "m2", minutesFromNow: -120),
        ]

        let status = try await scheduler.refreshOverdue(unresolvedDoses: missed, now: Fixture.now)

        XCTAssertEqual(status.badgeCount, 2)
        let badge = await center.badgeCount
        XCTAssertEqual(badge, 2)
        let summary = await center.pendingNotifications().first {
            $0.identifier == NotificationScheduler.overdueSummaryIdentifier
        }
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.content.badge, 2)
        XCTAssertEqual(summary?.content.categoryIdentifier, DoseNotificationCategories.overdueSummary)
    }

    func testRefreshOverdueClearsWhenNoneMissed() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)

        // First, create an overdue state.
        _ = try await scheduler.refreshOverdue(
            unresolvedDoses: [Fixture.dose(schedule: "m1", minutesFromNow: -60)],
            now: Fixture.now
        )
        // Then resolve everything.
        let status = try await scheduler.refreshOverdue(unresolvedDoses: [], now: Fixture.now)

        XCTAssertEqual(status.badgeCount, 0)
        let badge = await center.badgeCount
        XCTAssertEqual(badge, 0)
        let summary = await center.pendingNotifications().first {
            $0.identifier == NotificationScheduler.overdueSummaryIdentifier
        }
        XCTAssertNil(summary, "Summary must be cleared once no doses are overdue")
    }
}
