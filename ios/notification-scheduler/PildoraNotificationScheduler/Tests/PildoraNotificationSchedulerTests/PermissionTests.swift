import XCTest
@testable import PildoraNotificationScheduler

final class PermissionTests: XCTestCase {

    func testPromptsWhenUndetermined() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .notDetermined, grantOnRequest: true)
        let auth = NotificationAuthorization(center: center)

        let outcome = try await auth.requestIfNeeded()

        XCTAssertTrue(outcome.didPrompt)
        XCTAssertEqual(outcome.status, .authorized)
        XCTAssertTrue(outcome.canDeliver)
        let count = await center.authorizationRequestCount
        XCTAssertEqual(count, 1)
    }

    func testDeniedOnRequest() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .notDetermined, grantOnRequest: false)
        let auth = NotificationAuthorization(center: center)

        let outcome = try await auth.requestIfNeeded()

        XCTAssertTrue(outcome.didPrompt)
        XCTAssertEqual(outcome.status, .denied)
        XCTAssertFalse(outcome.canDeliver)
    }

    func testDoesNotRePromptOnceDecided() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .denied)
        let auth = NotificationAuthorization(center: center)

        let outcome = try await auth.requestIfNeeded()

        XCTAssertFalse(outcome.didPrompt)
        XCTAssertEqual(outcome.status, .denied)
        let count = await center.authorizationRequestCount
        XCTAssertEqual(count, 0, "Must not re-prompt a settled decision")
    }

    func testSchedulerRequestAuthorizationIsIdempotent() async throws {
        let center = InMemoryNotificationCenter(initialStatus: .notDetermined)
        let scheduler = NotificationScheduler(center: center)

        _ = try await scheduler.requestAuthorization()
        let second = try await scheduler.requestAuthorization()

        XCTAssertFalse(second.didPrompt)
        let count = await center.authorizationRequestCount
        XCTAssertEqual(count, 1)
    }

    func testRegisterCategoriesInstallsDoseAndOverdue() async {
        let center = InMemoryNotificationCenter(initialStatus: .authorized)
        let scheduler = NotificationScheduler(center: center)

        await scheduler.registerCategories()

        let categories = await center.categories
        XCTAssertEqual(
            Set(categories.map(\.identifier)),
            [DoseNotificationCategories.doseReminder, DoseNotificationCategories.overdueSummary]
        )
    }

    func testAuthorizationStatusCanDeliver() {
        XCTAssertTrue(NotificationAuthorizationStatus.authorized.canDeliver)
        XCTAssertTrue(NotificationAuthorizationStatus.provisional.canDeliver)
        XCTAssertFalse(NotificationAuthorizationStatus.denied.canDeliver)
        XCTAssertFalse(NotificationAuthorizationStatus.notDetermined.canDeliver)
    }
}
