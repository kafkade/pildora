import Foundation

/// A medication with its dosing schedule, used to compute future dose times.
struct MedicationSchedule: CustomStringConvertible {
    let id: String
    let name: String
    let dosesPerDay: Int
    /// Hour-of-day for each dose (e.g., [8, 14, 22] for 8 AM, 2 PM, 10 PM).
    let doseHours: [Int]
    let priority: DosePriority

    var description: String { "\(name) (\(dosesPerDay)x/day)" }

    /// Computes the next `count` dose times starting from `after`.
    func nextDoseTimes(after date: Date, count: Int) -> [ScheduledDose] {
        let calendar = Calendar.current
        var results: [ScheduledDose] = []
        var current = calendar.startOfDay(for: date)

        while results.count < count {
            for hour in doseHours {
                guard let doseTime = calendar.date(
                    bySettingHour: hour, minute: 0, second: 0, of: current
                ) else { continue }
                if doseTime > date {
                    results.append(ScheduledDose(
                        medicationId: id,
                        medicationName: name,
                        scheduledAt: doseTime,
                        priority: priority
                    ))
                    if results.count >= count { break }
                }
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return results
    }
}

/// Priority tier for dose notifications. Higher priority doses are scheduled
/// first when approaching the 64-notification ceiling.
enum DosePriority: Int, Comparable, CustomStringConvertible {
    case critical = 0    // Life-sustaining medications (e.g., insulin, immunosuppressants)
    case high = 1        // Prescription medications
    case normal = 2      // OTC medications
    case low = 3         // Supplements/vitamins

    static func < (lhs: DosePriority, rhs: DosePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .critical: return "critical"
        case .high: return "high"
        case .normal: return "normal"
        case .low: return "low"
        }
    }
}

/// A single scheduled dose ready to become a notification.
struct ScheduledDose: Comparable {
    let medicationId: String
    let medicationName: String
    let scheduledAt: Date
    let priority: DosePriority

    /// Unique identifier for the notification request.
    var notificationId: String {
        let ts = Int(scheduledAt.timeIntervalSince1970)
        return "\(medicationId)-\(ts)"
    }

    /// Sort by priority first (critical before low), then by time.
    static func < (lhs: ScheduledDose, rhs: ScheduledDose) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.scheduledAt < rhs.scheduledAt
    }
}
