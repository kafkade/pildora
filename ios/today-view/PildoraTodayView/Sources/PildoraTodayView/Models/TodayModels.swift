import Foundation

public enum DoseTimeWindow: String, CaseIterable, Codable, Sendable {
    case morning
    case afternoon
    case evening
    case bedtime

    public var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .bedtime: return "Bedtime"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        case .bedtime: return 3
        }
    }

    public static func window(for date: Date, calendar: Calendar = .current) -> DoseTimeWindow {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5...11: return .morning
        case 12...16: return .afternoon
        case 17...20: return .evening
        default: return .bedtime
        }
    }
}

public enum DoseState: String, CaseIterable, Codable, Sendable {
    case upcoming
    case dueNow
    case overdue
    case taken
    case skipped
    case snoozed

    public var displayText: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .dueNow: return "Due now"
        case .overdue: return "Overdue"
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }
}

public struct ScheduledDose: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var vaultId: String
    public var medicationID: String
    public var medicationName: String
    public var dosage: String
    public var scheduledAt: Date

    public init(
        id: String = UUID().uuidString,
        vaultId: String,
        medicationID: String,
        medicationName: String,
        dosage: String,
        scheduledAt: Date
    ) {
        self.id = id
        self.vaultId = vaultId
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.dosage = dosage
        self.scheduledAt = scheduledAt
    }
}

public struct PRNMedication: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var vaultId: String
    public var medicationName: String
    public var dosage: String

    public init(
        id: String = UUID().uuidString,
        vaultId: String,
        medicationName: String,
        dosage: String
    ) {
        self.id = id
        self.vaultId = vaultId
        self.medicationName = medicationName
        self.dosage = dosage
    }
}

public struct DoseLogEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var vaultId: String
    public var medicationID: String
    public var medicationName: String
    public var dosage: String
    public var scheduledDoseID: String?
    public var status: DoseState
    public var recordedAt: Date
    public var scheduledFor: Date?
    public var snoozedUntil: Date?
    public var note: String?

    public var isPRN: Bool { scheduledDoseID == nil }

    public init(
        id: String = UUID().uuidString,
        vaultId: String,
        medicationID: String,
        medicationName: String,
        dosage: String,
        scheduledDoseID: String?,
        status: DoseState,
        recordedAt: Date,
        scheduledFor: Date?,
        snoozedUntil: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.vaultId = vaultId
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.dosage = dosage
        self.scheduledDoseID = scheduledDoseID
        self.status = status
        self.recordedAt = recordedAt
        self.scheduledFor = scheduledFor
        self.snoozedUntil = snoozedUntil
        self.note = note
    }
}

public struct TodayDoseItem: Identifiable, Hashable, Sendable {
    public let dose: ScheduledDose
    public let state: DoseState
    public let log: DoseLogEntry?

    public init(dose: ScheduledDose, state: DoseState, log: DoseLogEntry?) {
        self.dose = dose
        self.state = state
        self.log = log
    }

    public var id: String { dose.id }
}

public struct TodaySection: Identifiable, Hashable, Sendable {
    public let window: DoseTimeWindow
    public let doses: [TodayDoseItem]

    public init(window: DoseTimeWindow, doses: [TodayDoseItem]) {
        self.window = window
        self.doses = doses
    }

    public var id: DoseTimeWindow { window }
}
