import XCTest
@testable import PildoraNotificationScheduler

final class SnoozeTests: XCTestCase {

    func testSnoozeSchedulesOneShotReminder() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        _ = try await scheduler.replenish(candidates: [dose], now: Fixture.now)

        let result = try await scheduler.apply(
            action: .snooze(minutes: 15), to: dose, now: Fixture.now
        )

        XCTAssertEqual(result.snoozedUntil, Fixture.now.addingTimeInterval(15 * 60))
        let snoozes = await center.pendingNotifications().filter {
            $0.identifier.hasPrefix(NotificationScheduler.snoozeIdentifierPrefix)
        }
        XCTAssertEqual(snoozes.count, 1)
        XCTAssertEqual(snoozes.first?.fireDate, Fixture.now.addingTimeInterval(15 * 60))
    }

    func testSnoozeSurvivesReplenish() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)

        _ = try await scheduler.apply(action: .snooze(minutes: 10), to: dose, now: Fixture.now)
        // A later replenishment (remove-all dose notifications) must not clear
        // the pending snooze — it does not carry the dose prefix.
        let others = (0..<3).map { Fixture.dose(schedule: "other\($0)", minutesFromNow: 30 + $0) }
        _ = try await scheduler.replenish(candidates: others, now: Fixture.now)

        let snoozes = await center.pendingNotifications().filter {
            $0.identifier.hasPrefix(NotificationScheduler.snoozeIdentifierPrefix)
        }
        XCTAssertEqual(snoozes.count, 1, "Snooze must survive rotation")
    }

    func testSnoozePresets() {
        XCTAssertEqual(SnoozeOption.tenMinutes.minutes, 10)
        XCTAssertEqual(SnoozeOption.fifteenMinutes.minutes, 15)
        XCTAssertEqual(SnoozeOption.thirtyMinutes.minutes, 30)
        XCTAssertEqual(SnoozeOption.default, .fifteenMinutes)
        XCTAssertEqual(SnoozeOption.thirtyMinutes.actionTitle, "Snooze 30m")
    }

    func testSnoozeClampsNonPositiveMinutes() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)

        let result = try await scheduler.apply(action: .snooze(minutes: 0), to: dose, now: Fixture.now)
        XCTAssertEqual(result.snoozedUntil, Fixture.now.addingTimeInterval(60))
    }

    func testReSnoozeReplacesPriorSnooze() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)

        _ = try await scheduler.apply(action: .snooze(minutes: 10), to: dose, now: Fixture.now)
        _ = try await scheduler.apply(action: .snooze(minutes: 30), to: dose, now: Fixture.now)

        let snoozes = await center.pendingNotifications().filter {
            $0.identifier.hasPrefix(NotificationScheduler.snoozeIdentifierPrefix)
        }
        XCTAssertEqual(snoozes.count, 1)
        XCTAssertEqual(snoozes.first?.fireDate, Fixture.now.addingTimeInterval(30 * 60))
    }
}
