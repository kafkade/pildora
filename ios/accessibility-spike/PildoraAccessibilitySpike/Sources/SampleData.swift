import Foundation

// MARK: - Domain Types

enum DoseStatus: String, CaseIterable {
    case upcoming = "Upcoming"
    case due = "Due now"
    case taken = "Taken"
    case missed = "Missed"
    case skipped = "Skipped"
}

enum MedicationForm: String {
    case tablet = "tablet"
    case capsule = "capsule"
    case liquid = "liquid"
    case injection = "injection"
    case patch = "patch"
    case drops = "drops"
}

struct SampleMedication: Identifiable {
    let id: String
    let name: String
    let genericName: String?
    let dosage: String
    let form: MedicationForm
    let frequency: String
    let nextDoseTime: Date?
    let lastDoseStatus: DoseStatus
    let inventoryRemaining: Int?
    let inventoryDaysSupply: Int?
    let dosesPerDay: Int
    let prescriber: String?

    var isLowInventory: Bool {
        guard let remaining = inventoryRemaining else { return false }
        return remaining <= 7
    }

    var statusDescription: String {
        switch lastDoseStatus {
        case .upcoming:
            if let time = nextDoseTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                return "Due \(formatter.localizedString(for: time, relativeTo: Date()))"
            }
            return "Upcoming"
        case .due:
            return "Due now"
        case .taken:
            return "Taken today"
        case .missed:
            return "Missed — overdue"
        case .skipped:
            return "Skipped"
        }
    }

    var inventoryDescription: String? {
        guard let remaining = inventoryRemaining else { return nil }
        if remaining <= 3 {
            return "Critical: \(remaining) \(form.rawValue)s left"
        } else if remaining <= 7 {
            return "Low: \(remaining) \(form.rawValue)s left"
        }
        return "\(remaining) \(form.rawValue)s remaining"
    }

    var accessibilityDescription: String {
        var parts = ["\(name), \(dosage) \(form.rawValue)"]
        if let generic = genericName {
            parts.append("generic: \(generic)")
        }
        parts.append(frequency)
        parts.append(statusDescription)
        if let inv = inventoryDescription {
            parts.append(inv)
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Sample Data

/// Five medications chosen to stress-test accessibility edge cases.
///
/// Coverage:
/// 1. Overdue/missed dose (urgency coloring + VoiceOver announcement)
/// 2. Already taken dose (success state)
/// 3. Upcoming dose with long medication name (layout stress)
/// 4. Low inventory + supplement (refill warning)
/// 5. Multi-daily dose with due-now status
struct SampleData {
    static let now = Date()
    static let calendar = Calendar.current

    static let medications: [SampleMedication] = [
        // 1. MISSED: Critical medication — tests urgency state + VoiceOver priority
        SampleMedication(
            id: "med-1",
            name: "Levothyroxine",
            genericName: nil,
            dosage: "88 mcg",
            form: .tablet,
            frequency: "Once daily, morning on empty stomach",
            nextDoseTime: calendar.date(byAdding: .hour, value: -3, to: now),
            lastDoseStatus: .missed,
            inventoryRemaining: 22,
            inventoryDaysSupply: 22,
            dosesPerDay: 1,
            prescriber: "Dr. Chen"
        ),

        // 2. TAKEN: Standard Rx — tests success/completed state
        SampleMedication(
            id: "med-2",
            name: "Metformin",
            genericName: "metformin hydrochloride",
            dosage: "500 mg",
            form: .tablet,
            frequency: "Twice daily with meals",
            nextDoseTime: calendar.date(byAdding: .hour, value: 5, to: now),
            lastDoseStatus: .taken,
            inventoryRemaining: 45,
            inventoryDaysSupply: 22,
            dosesPerDay: 2,
            prescriber: "Dr. Patel"
        ),

        // 3. UPCOMING: Very long name — stresses Dynamic Type layout wrapping
        SampleMedication(
            id: "med-3",
            name: "Cholecalciferol (Vitamin D3)",
            genericName: "cholecalciferol",
            dosage: "5,000 IU",
            form: .capsule,
            frequency: "Once daily",
            nextDoseTime: calendar.date(byAdding: .hour, value: 2, to: now),
            lastDoseStatus: .upcoming,
            inventoryRemaining: 90,
            inventoryDaysSupply: 90,
            dosesPerDay: 1,
            prescriber: nil
        ),

        // 4. LOW INVENTORY: Supplement with refill warning
        SampleMedication(
            id: "med-4",
            name: "Magnesium Glycinate",
            genericName: nil,
            dosage: "400 mg",
            form: .capsule,
            frequency: "Once daily at bedtime",
            nextDoseTime: calendar.date(byAdding: .hour, value: 8, to: now),
            lastDoseStatus: .upcoming,
            inventoryRemaining: 3,
            inventoryDaysSupply: 3,
            dosesPerDay: 1,
            prescriber: nil
        ),

        // 5. DUE NOW: Multi-daily Rx — tests actionable/urgent current state
        SampleMedication(
            id: "med-5",
            name: "Gabapentin",
            genericName: nil,
            dosage: "300 mg",
            form: .capsule,
            frequency: "Three times daily",
            nextDoseTime: now,
            lastDoseStatus: .due,
            inventoryRemaining: 15,
            inventoryDaysSupply: 5,
            dosesPerDay: 3,
            prescriber: "Dr. Rivera"
        ),
    ]

    /// The dose currently being confirmed (Gabapentin — due now).
    static var currentDose: SampleMedication { medications[4] }
}
