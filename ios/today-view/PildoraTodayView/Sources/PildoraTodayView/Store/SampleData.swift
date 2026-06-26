import Foundation

public enum TodaySampleData {
    public static let vaultId = "vault-default"

    public static func scheduledDoses(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScheduledDose] {
        let dayStart = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
        }

        return [
            ScheduledDose(id: "dose-omeprazole-am", vaultId: vaultId, medicationID: "med-omeprazole", medicationName: "Omeprazole", dosage: "20 mg", scheduledAt: at(6, 30)),
            ScheduledDose(id: "dose-levothyroxine-am", vaultId: vaultId, medicationID: "med-levothyroxine", medicationName: "Levothyroxine", dosage: "88 mcg", scheduledAt: at(7, 0)),
            ScheduledDose(id: "dose-probiotic-am", vaultId: vaultId, medicationID: "med-probiotic", medicationName: "Probiotic Blend", dosage: "1 capsule", scheduledAt: at(7, 30)),
            ScheduledDose(id: "dose-metformin-am", vaultId: vaultId, medicationID: "med-metformin", medicationName: "Metformin", dosage: "500 mg", scheduledAt: at(8, 0)),
            ScheduledDose(id: "dose-aspirin-am", vaultId: vaultId, medicationID: "med-aspirin", medicationName: "Aspirin", dosage: "81 mg", scheduledAt: at(8, 30)),
            ScheduledDose(id: "dose-b12-am", vaultId: vaultId, medicationID: "med-b12", medicationName: "Vitamin B12", dosage: "1,000 mcg", scheduledAt: at(9, 30)),
            ScheduledDose(id: "dose-vitamin-d-noon", vaultId: vaultId, medicationID: "med-vitamin-d", medicationName: "Cholecalciferol (Vitamin D3)", dosage: "5,000 IU", scheduledAt: at(12, 30)),
            ScheduledDose(id: "dose-gabapentin-noon", vaultId: vaultId, medicationID: "med-gabapentin", medicationName: "Gabapentin", dosage: "300 mg", scheduledAt: at(14, 0)),
            ScheduledDose(id: "dose-omega3-afternoon", vaultId: vaultId, medicationID: "med-omega3", medicationName: "Omega-3 Fish Oil", dosage: "1 capsule", scheduledAt: at(15, 30)),
            ScheduledDose(id: "dose-calcium-evening", vaultId: vaultId, medicationID: "med-calcium", medicationName: "Calcium Citrate", dosage: "600 mg", scheduledAt: at(18, 0)),
            ScheduledDose(id: "dose-magnesium-evening", vaultId: vaultId, medicationID: "med-magnesium", medicationName: "Magnesium Glycinate", dosage: "400 mg", scheduledAt: at(19, 30)),
            ScheduledDose(id: "dose-atorvastatin-evening", vaultId: vaultId, medicationID: "med-atorvastatin", medicationName: "Atorvastatin", dosage: "20 mg", scheduledAt: at(20, 0)),
            ScheduledDose(id: "dose-gabapentin-evening", vaultId: vaultId, medicationID: "med-gabapentin", medicationName: "Gabapentin", dosage: "300 mg", scheduledAt: at(21, 0)),
            ScheduledDose(id: "dose-cetirizine-bedtime", vaultId: vaultId, medicationID: "med-cetirizine", medicationName: "Cetirizine", dosage: "10 mg", scheduledAt: at(22, 0)),
            ScheduledDose(id: "dose-melatonin-bedtime", vaultId: vaultId, medicationID: "med-melatonin", medicationName: "Melatonin", dosage: "3 mg", scheduledAt: at(22, 30)),
            ScheduledDose(id: "dose-metformin-bedtime", vaultId: vaultId, medicationID: "med-metformin", medicationName: "Metformin", dosage: "500 mg", scheduledAt: at(23, 0)),
        ]
    }

    public static func prnMedications() -> [PRNMedication] {
        [
            PRNMedication(id: "prn-ibuprofen", vaultId: vaultId, medicationName: "Ibuprofen", dosage: "200 mg"),
            PRNMedication(id: "prn-albuterol", vaultId: vaultId, medicationName: "Albuterol inhaler", dosage: "2 puffs"),
        ]
    }

    public static func seedLogs(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DoseLogEntry] {
        let byID = Dictionary(
            uniqueKeysWithValues: scheduledDoses(now: now, calendar: calendar).map { ($0.id, $0) }
        )
        guard
            let metforminAM = byID["dose-metformin-am"],
            let levothyroxineAM = byID["dose-levothyroxine-am"],
            let gabapentinNoon = byID["dose-gabapentin-noon"]
        else {
            return []
        }

        let skipTime = calendar.date(byAdding: .minute, value: 10, to: levothyroxineAM.scheduledAt) ?? levothyroxineAM.scheduledAt
        let takenTime = calendar.date(byAdding: .minute, value: 5, to: metforminAM.scheduledAt) ?? metforminAM.scheduledAt
        let snoozeTime = calendar.date(byAdding: .minute, value: -5, to: now) ?? now
        let snoozedUntil = calendar.date(byAdding: .minute, value: 15, to: now) ?? now

        return [
            DoseLogEntry(
                id: "log-metformin-am-taken",
                vaultId: vaultId,
                medicationID: metforminAM.medicationID,
                medicationName: metforminAM.medicationName,
                dosage: metforminAM.dosage,
                scheduledDoseID: metforminAM.id,
                status: .taken,
                recordedAt: takenTime,
                scheduledFor: metforminAM.scheduledAt
            ),
            DoseLogEntry(
                id: "log-levothyroxine-am-skipped",
                vaultId: vaultId,
                medicationID: levothyroxineAM.medicationID,
                medicationName: levothyroxineAM.medicationName,
                dosage: levothyroxineAM.dosage,
                scheduledDoseID: levothyroxineAM.id,
                status: .skipped,
                recordedAt: skipTime,
                scheduledFor: levothyroxineAM.scheduledAt,
                note: "Missed fasting window"
            ),
            DoseLogEntry(
                id: "log-gabapentin-noon-snoozed",
                vaultId: vaultId,
                medicationID: gabapentinNoon.medicationID,
                medicationName: gabapentinNoon.medicationName,
                dosage: gabapentinNoon.dosage,
                scheduledDoseID: gabapentinNoon.id,
                status: .snoozed,
                recordedAt: snoozeTime,
                scheduledFor: gabapentinNoon.scheduledAt,
                snoozedUntil: snoozedUntil
            ),
        ]
    }
}
