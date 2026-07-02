import XCTest
@testable import PildoraNotificationScheduler

final class ActionHandlingTests: XCTestCase {

    func testReplenishSchedulesDoseNotifications() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let candidates = (0..<5).map { Fixture.dose(schedule: "s\($0)", minutesFromNow: 10 + $0 * 10) }

        let plan = try await scheduler.replenish(candidates: candidates, now: Fixture.now)

        XCTAssertEqual(plan.scheduled.count, 5)
        let pending = await center.pendingDoseNotifications()
        XCTAssertEqual(pending.count, 5)
        XCTAssertTrue(pending.allSatisfy { $0.identifier.hasPrefix(DoseNotification.identifierPrefix) })
    }

    func testReplenishIsIdempotentRotation() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let candidates = (0..<5).map { Fixture.dose(schedule: "s\($0)", minutesFromNow: 10 + $0 * 10) }

        _ = try await scheduler.replenish(candidates: candidates, now: Fixture.now)
        _ = try await scheduler.replenish(candidates: candidates, now: Fixture.now)

        let pending = await center.pendingDoseNotifications()
        XCTAssertEqual(pending.count, 5, "Re-replenish must not duplicate notifications")
    }

    func testTakenClearsReminderAndReturnsResult() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        _ = try await scheduler.replenish(candidates: [dose], now: Fixture.now)

        let result = try await scheduler.apply(action: .taken, to: dose, now: Fixture.now)

        XCTAssertEqual(result.action, .taken)
        XCTAssertNil(result.snoozedUntil)
        let pending = await center.pendingIdentifiers()
        XCTAssertFalse(pending.contains(dose.id))
    }

    func testSkipClearsReminder() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        _ = try await scheduler.replenish(candidates: [dose], now: Fixture.now)

        let result = try await scheduler.apply(action: .skip, to: dose, now: Fixture.now)

        XCTAssertEqual(result.action, .skip)
        let pending = await center.pendingIdentifiers()
        XCTAssertFalse(pending.contains(dose.id))
    }

    func testHandleReplenishesAfterAction() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        // 62 future doses; only 60 fit. Acting on one and replenishing should
        // backfill from the two that were dropped.
        let all = (0..<62).map { Fixture.dose(schedule: "s\($0)", minutesFromNow: 10 + $0) }
        _ = try await scheduler.replenish(candidates: all, now: Fixture.now)
        var pending = await center.pendingDoseNotifications()
        XCTAssertEqual(pending.count, 60)

        // The acted-on dose is one that was scheduled; after it, candidates no
        // longer include it, and replenish fills the freed slots.
        let acted = all[0]
        let remaining = Array(all.dropFirst())
        _ = try await scheduler.handle(action: .taken, for: acted, candidates: remaining, now: Fixture.now)

        pending = await center.pendingDoseNotifications()
        XCTAssertEqual(pending.count, 60)
        XCTAssertFalse(pending.contains { $0.identifier == acted.id })
    }

    func testContentCarriesOnlyIdentifiersNotHealthData() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        _ = try await scheduler.replenish(candidates: [dose], now: Fixture.now)

        let planned = await center.pendingDoseNotifications().first
        let keys = planned.map { Set($0.content.userInfo.keys) } ?? []
        XCTAssertEqual(keys, ["scheduleId", "medicationId", "vaultId"])
    }
}
