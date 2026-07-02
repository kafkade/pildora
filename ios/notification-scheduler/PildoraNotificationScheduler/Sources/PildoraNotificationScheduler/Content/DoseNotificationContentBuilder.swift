import Foundation

// MARK: - DoseNotificationContentBuilder

/// Builds the user-facing content for dose reminders and the overdue summary.
///
/// Content is assembled entirely on-device from the medication metadata already
/// present on each ``DoseNotification``.
///
/// > Zero-knowledge: nothing here is sent to a server. > No medical advice: the
/// > body states what/how-much/when-and-any-instructions the user themselves
/// > entered; it never adds dosing guidance or interpretation.
public struct DoseNotificationContentBuilder: Sendable {

    public init() {}

    /// The reminder content for a single dose.
    ///
    /// - Title: the medication name.
    /// - Body: "Time to take <dosage>", plus any user instructions.
    public func content(for dose: DoseNotification) -> NotificationContent {
        NotificationContent(
            title: dose.medicationName,
            body: body(for: dose),
            categoryIdentifier: DoseNotificationCategories.doseReminder,
            threadIdentifier: DoseNotificationCategories.doseThread,
            badge: nil,
            playsSound: true,
            userInfo: [
                "scheduleId": dose.scheduleId,
                "medicationId": dose.medicationId,
                "vaultId": dose.vaultId,
            ]
        )
    }

    /// A ``PlannedNotification`` (content + identifier + fire time) for a dose.
    public func plannedNotification(for dose: DoseNotification) -> PlannedNotification {
        PlannedNotification(
            identifier: dose.id,
            content: content(for: dose),
            fireDate: dose.scheduledAt
        )
    }

    /// The single summary notification shown when doses are overdue. Fires
    /// immediately (a few seconds out) and carries the missed-dose badge.
    public func overdueSummaryContent(missedCount: Int) -> NotificationContent {
        let doseWord = missedCount == 1 ? "dose" : "doses"
        return NotificationContent(
            title: "Missed \(missedCount) \(doseWord)",
            body: "You have \(missedCount) overdue \(doseWord). Open Pildora to review.",
            categoryIdentifier: DoseNotificationCategories.overdueSummary,
            threadIdentifier: DoseNotificationCategories.doseThread,
            badge: missedCount,
            playsSound: false,
            userInfo: ["kind": "overdue-summary"]
        )
    }

    // MARK: - Body composition

    private func body(for dose: DoseNotification) -> String {
        var line: String
        if let dosage = dose.dosage, !dosage.trimmingCharacters(in: .whitespaces).isEmpty {
            line = "Time to take \(dosage)"
        } else {
            line = "Time to take \(dose.medicationName)"
        }
        if let instructions = dose.instructions,
           !instructions.trimmingCharacters(in: .whitespaces).isEmpty {
            line += " — \(instructions)"
        }
        return line
    }
}
