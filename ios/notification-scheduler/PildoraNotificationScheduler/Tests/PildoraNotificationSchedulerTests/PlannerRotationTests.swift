import XCTest
@testable import PildoraNotificationScheduler

final class PlannerRotationTests: XCTestCase {

    func testDropsPastAndAtNowDoses() {
        let planner = NotificationPlanner()
        let candidates = [
            Fixture.dose(schedule: "a", minutesFromNow: -30),
            Fixture.dose(schedule: "b", minutesFromNow: 0),
            Fixture.dose(schedule: "c", minutesFromNow: 30),
        ]
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        XCTAssertEqual(plan.scheduled.map(\.scheduleId), ["c"])
    }

    func testDeduplicatesByIdentifier() {
        let planner = NotificationPlanner()
        let dose = Fixture.dose(schedule: "a", minutesFromNow: 60)
        let plan = planner.plan(candidates: [dose, dose, dose], now: Fixture.now)
        XCTAssertEqual(plan.scheduled.count, 1)
    }

    func testOrdersByTimeThenPriority() {
        let planner = NotificationPlanner()
        let candidates = [
            Fixture.dose(schedule: "low-soon", minutesFromNow: 10, priority: .low),
            Fixture.dose(schedule: "critical-late", minutesFromNow: 600, priority: .critical),
            Fixture.dose(schedule: "high-mid", minutesFromNow: 120, priority: .high),
            Fixture.dose(schedule: "critical-soon", minutesFromNow: 30, priority: .critical),
        ]
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        // Pure chronological order — soonest first regardless of priority.
        XCTAssertEqual(
            plan.scheduled.map(\.scheduleId),
            ["low-soon", "critical-soon", "high-mid", "critical-late"]
        )
    }

    func testPriorityBreaksTiesAtSameInstant() {
        let planner = NotificationPlanner()
        let candidates = [
            Fixture.dose(schedule: "vitamin", minutesFromNow: 60, priority: .low),
            Fixture.dose(schedule: "insulin", minutesFromNow: 60, priority: .critical),
            Fixture.dose(schedule: "aspirin", minutesFromNow: 60, priority: .normal),
        ]
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        XCTAssertEqual(plan.scheduled.map(\.scheduleId), ["insulin", "aspirin", "vitamin"])
    }

    func testNeverExceedsBudget() {
        let planner = NotificationPlanner(budget: .default)
        // 100 future doses; budget allows 60.
        let candidates = (0..<100).map {
            Fixture.dose(schedule: "s\($0)", minutesFromNow: 10 + $0)
        }
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        XCTAssertEqual(plan.scheduled.count, 60)
        XCTAssertEqual(plan.dropped.count, 40)
        XCTAssertEqual(plan.candidateCount, 100)
    }

    func testFurthestDosesDroppedUnderPressure() {
        let planner = NotificationPlanner(budget: NotificationBudget(reservedSlots: 62)) // 2 dose slots
        let candidates = [
            Fixture.dose(schedule: "vitamin", minutesFromNow: 5, priority: .low),
            Fixture.dose(schedule: "insulin", minutesFromNow: 500, priority: .critical),
            Fixture.dose(schedule: "statin", minutesFromNow: 200, priority: .high),
        ]
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        // Soonest two kept so nothing imminent is starved; the furthest-out dose
        // is deferred to the next replenishment cycle.
        XCTAssertEqual(plan.scheduled.map(\.scheduleId), ["vitamin", "statin"])
        XCTAssertEqual(plan.dropped.map(\.scheduleId), ["insulin"])
    }

    func testCoverageHours() {
        let planner = NotificationPlanner()
        let candidates = [
            Fixture.dose(schedule: "a", minutesFromNow: 60),
            Fixture.dose(schedule: "b", minutesFromNow: 180),
        ]
        let plan = planner.plan(candidates: candidates, now: Fixture.now)
        XCTAssertEqual(plan.coverageHours(from: Fixture.now), 3.0, accuracy: 0.001)
    }

    func testBudgetMath() {
        XCTAssertEqual(NotificationBudget.default.maxDoseNotifications, 60)
        XCTAssertEqual(NotificationBudget(reservedSlots: 0).maxDoseNotifications, 64)
    }
}
