import Foundation
@testable import PildoraNotificationScheduler

// MARK: - Test support

enum Fixture {

    /// A fixed reference instant used across tests for determinism:
    /// 2026-01-05 08:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_767_600_000)

    static let vaultId = "vault-1"

    /// Builds a dose notification `minutes` after `base`.
    static func dose(
        schedule: String,
        medication: String? = nil,
        name: String = "Med",
        dosage: String? = "1 tablet",
        instructions: String? = nil,
        minutesFromNow minutes: Int,
        base: Date = now,
        priority: DosePriority = .normal
    ) -> DoseNotification {
        DoseNotification(
            scheduleId: schedule,
            medicationId: medication ?? schedule,
            vaultId: vaultId,
            medicationName: name,
            dosage: dosage,
            instructions: instructions,
            scheduledAt: base.addingTimeInterval(TimeInterval(minutes * 60)),
            priority: priority
        )
    }

    /// Generates `count` medications, each dosed `dosesPerDay` times a day at
    /// evenly spaced hours across `days`, starting from `base`. Priorities cycle
    /// through the tiers so ordering behavior is exercised.
    static func schedules(
        medications count: Int,
        dosesPerDay: Int,
        days: Int,
        base: Date = now
    ) -> [DoseNotification] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let priorities = DosePriority.allCases
        var doses: [DoseNotification] = []

        for med in 0..<count {
            let priority = priorities[med % priorities.count]
            let startHour = 8
            let spacing = max(1, 14 / max(1, dosesPerDay)) // spread across the day
            let startDay = calendar.startOfDay(for: base)
            for day in 0..<days {
                guard let dayStart = calendar.date(byAdding: .day, value: day, to: startDay) else { continue }
                for i in 0..<dosesPerDay {
                    let hour = startHour + i * spacing
                    guard let fire = calendar.date(
                        bySettingHour: min(hour, 23), minute: (med % 4) * 5, second: 0, of: dayStart
                    ) else { continue }
                    guard fire > base else { continue }
                    doses.append(DoseNotification(
                        scheduleId: "sched-\(med)-\(day)-\(i)",
                        medicationId: "med-\(med)",
                        vaultId: vaultId,
                        medicationName: "Medication \(med)",
                        dosage: "\(med + 1) mg",
                        instructions: nil,
                        scheduledAt: fire,
                        priority: priority
                    ))
                }
            }
        }
        return doses
    }
}
