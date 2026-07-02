import Foundation

// MARK: - NotificationAuthorization

/// Thin wrapper coordinating the onboarding notification-permission request.
///
/// Encapsulates the "only prompt once, when undetermined" rule so the onboarding
/// flow can call ``requestIfNeeded()`` idempotently without re-prompting a user
/// who already made a decision.
public struct NotificationAuthorization: Sendable {

    private let center: NotificationScheduling

    public init(center: NotificationScheduling) {
        self.center = center
    }

    /// The current authorization status.
    public func status() async -> NotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    /// The result of an authorization attempt.
    public struct Outcome: Equatable, Sendable {
        /// Whether a system prompt was actually shown this call.
        public var didPrompt: Bool
        /// The resulting status.
        public var status: NotificationAuthorizationStatus
        /// Whether reminders can now be delivered.
        public var canDeliver: Bool { status.canDeliver }
    }

    /// Requests authorization only if the user has not yet decided.
    ///
    /// - If undetermined: shows the system prompt and returns the result.
    /// - Otherwise: returns the settled status without prompting.
    @discardableResult
    public func requestIfNeeded() async throws -> Outcome {
        let current = await center.authorizationStatus()
        guard current == .notDetermined else {
            return Outcome(didPrompt: false, status: current)
        }
        _ = try await center.requestAuthorization()
        let updated = await center.authorizationStatus()
        return Outcome(didPrompt: true, status: updated)
    }
}
