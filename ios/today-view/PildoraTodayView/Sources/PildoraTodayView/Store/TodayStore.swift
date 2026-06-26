import Foundation
import Combine

@MainActor
public final class TodayStore: ObservableObject {
    @Published public private(set) var scheduledDoses: [ScheduledDose]
    @Published public private(set) var prnMedications: [PRNMedication]
    @Published public private(set) var doseLogs: [DoseLogEntry]
    @Published public var now: Date

    private let calendar: Calendar

    public init(
        scheduledDoses: [ScheduledDose],
        prnMedications: [PRNMedication],
        doseLogs: [DoseLogEntry] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.scheduledDoses = scheduledDoses
        self.prnMedications = prnMedications
        self.doseLogs = doseLogs
        self.now = now
        self.calendar = calendar
    }

    public static func sample(now: Date = Date(), calendar: Calendar = .current) -> TodayStore {
        TodayStore(
            scheduledDoses: TodaySampleData.scheduledDoses(now: now, calendar: calendar),
            prnMedications: TodaySampleData.prnMedications(),
            doseLogs: TodaySampleData.seedLogs(now: now, calendar: calendar),
            now: now,
            calendar: calendar
        )
    }

    public func advanceClock(to date: Date) {
        now = date
    }

    public var doseItems: [TodayDoseItem] {
        scheduledDoses
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .map { dose in
                let resolved = resolveState(for: dose, at: now)
                return TodayDoseItem(dose: dose, state: resolved.state, log: resolved.log)
            }
    }

    public var sections: [TodaySection] {
        let grouped = Dictionary(grouping: doseItems) {
            DoseTimeWindow.window(for: $0.dose.scheduledAt, calendar: calendar)
        }
        return grouped
            .map { window, doses in
                TodaySection(window: window, doses: doses.sorted { $0.dose.scheduledAt < $1.dose.scheduledAt })
            }
            .sorted { $0.window.sortOrder < $1.window.sortOrder }
    }

    public var hasScheduledDoses: Bool {
        !scheduledDoses.isEmpty
    }

    public var allScheduledDosesResolved: Bool {
        !scheduledDoses.isEmpty
            && doseItems.allSatisfy { item in
                item.state == .taken || item.state == .skipped
            }
    }

    public var prnHistoryToday: [DoseLogEntry] {
        doseLogs
            .filter { $0.isPRN && calendar.isDate($0.recordedAt, inSameDayAs: now) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    public func markTaken(doseID: String, at date: Date = Date()) {
        guard let dose = scheduledDoses.first(where: { $0.id == doseID }) else {
            assertionFailure("Attempted to mark unknown dose '\(doseID)' as taken.")
            return
        }
        now = date
        upsertScheduledLog(
            for: dose,
            status: .taken,
            recordedAt: date
        )
    }

    public func skipDose(doseID: String, reason: String? = nil, at date: Date = Date()) {
        guard let dose = scheduledDoses.first(where: { $0.id == doseID }) else {
            assertionFailure("Attempted to skip unknown dose '\(doseID)'.")
            return
        }
        now = date
        upsertScheduledLog(
            for: dose,
            status: .skipped,
            recordedAt: date,
            note: reason
        )
    }

    public func snoozeDose(doseID: String, minutes: Int = 15, at date: Date = Date()) {
        guard let dose = scheduledDoses.first(where: { $0.id == doseID }) else {
            assertionFailure("Attempted to snooze unknown dose '\(doseID)'.")
            return
        }
        now = date
        let clampedMinutes = max(1, minutes)
        let until = calendar.date(byAdding: .minute, value: clampedMinutes, to: date) ?? date
        upsertScheduledLog(
            for: dose,
            status: .snoozed,
            recordedAt: date,
            snoozedUntil: until,
            note: "Snoozed \(clampedMinutes) min"
        )
    }

    public func logPRN(medicationID: String, at date: Date = Date()) {
        guard let med = prnMedications.first(where: { $0.id == medicationID }) else {
            assertionFailure("Attempted to log unknown PRN medication '\(medicationID)'.")
            return
        }
        now = date
        let entry = DoseLogEntry(
            vaultId: med.vaultId,
            medicationID: med.id,
            medicationName: med.medicationName,
            dosage: med.dosage,
            scheduledDoseID: nil,
            status: .taken,
            recordedAt: date,
            scheduledFor: nil,
            note: "PRN quick log"
        )
        doseLogs.append(entry)
        doseLogs.sort { $0.recordedAt > $1.recordedAt }
    }

    public func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func resolveState(for dose: ScheduledDose, at now: Date) -> (state: DoseState, log: DoseLogEntry?) {
        if let log = latestLog(forDoseID: dose.id) {
            switch log.status {
            case .taken, .skipped:
                return (log.status, log)
            case .snoozed:
                if let snoozedUntil = log.snoozedUntil, now >= snoozedUntil {
                    return (.dueNow, log)
                }
                return (.snoozed, log)
            case .upcoming, .dueNow, .overdue:
                break
            }
        }

        let delta = dose.scheduledAt.timeIntervalSince(now)
        if delta > 15 * 60 {
            return (.upcoming, nil)
        }
        if delta >= -30 * 60 {
            return (.dueNow, nil)
        }
        return (.overdue, nil)
    }

    private func latestLog(forDoseID doseID: String) -> DoseLogEntry? {
        doseLogs
            .filter { $0.scheduledDoseID == doseID }
            .max { $0.recordedAt < $1.recordedAt }
    }

    private func upsertScheduledLog(
        for dose: ScheduledDose,
        status: DoseState,
        recordedAt: Date,
        snoozedUntil: Date? = nil,
        note: String? = nil
    ) {
        doseLogs.removeAll { $0.scheduledDoseID == dose.id }
        let entry = DoseLogEntry(
            vaultId: dose.vaultId,
            medicationID: dose.medicationID,
            medicationName: dose.medicationName,
            dosage: dose.dosage,
            scheduledDoseID: dose.id,
            status: status,
            recordedAt: recordedAt,
            scheduledFor: dose.scheduledAt,
            snoozedUntil: snoozedUntil,
            note: note
        )
        doseLogs.append(entry)
        doseLogs.sort { $0.recordedAt > $1.recordedAt }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
