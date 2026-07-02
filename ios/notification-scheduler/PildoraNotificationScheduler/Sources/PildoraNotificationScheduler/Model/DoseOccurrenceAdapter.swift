import Foundation

// MARK: - DoseOccurrenceLike

/// The subset of the schedule engine's `DoseOccurrence` this package consumes.
///
/// The package is deliberately **dependency-free** (matching `today-view` and
/// `schedule-engine`), so it does not import `PildoraScheduleEngine`. Instead,
/// the app conforms the engine's `DoseOccurrence` to this protocol in one line
/// at the wiring layer:
///
/// ```swift
/// import PildoraScheduleEngine
/// import PildoraNotificationScheduler
///
/// extension DoseOccurrence: DoseOccurrenceLike {}
/// ```
///
/// `DoseOccurrence` already exposes `scheduleId`, `medicationId`, `vaultId`, and
/// `scheduledAt` with matching names/types, so the conformance needs no members.
public protocol DoseOccurrenceLike {
    var scheduleId: String { get }
    var medicationId: String { get }
    var vaultId: String { get }
    var scheduledAt: Date { get }
}

// MARK: - Adapter

extension DoseNotification {
    /// Builds a ``DoseNotification`` from a schedule-engine occurrence plus the
    /// display metadata the engine does not carry (name, dosage, instructions,
    /// priority all live with the medication record, not the occurrence).
    public init(
        occurrence: DoseOccurrenceLike,
        medicationName: String,
        dosage: String? = nil,
        instructions: String? = nil,
        priority: DosePriority = .normal
    ) {
        self.init(
            scheduleId: occurrence.scheduleId,
            medicationId: occurrence.medicationId,
            vaultId: occurrence.vaultId,
            medicationName: medicationName,
            dosage: dosage,
            instructions: instructions,
            scheduledAt: occurrence.scheduledAt,
            priority: priority
        )
    }

    /// Maps a batch of occurrences for a single medication into dose
    /// notifications, applying the same display metadata to each.
    public static func from(
        occurrences: [DoseOccurrenceLike],
        medicationName: String,
        dosage: String? = nil,
        instructions: String? = nil,
        priority: DosePriority = .normal
    ) -> [DoseNotification] {
        occurrences.map {
            DoseNotification(
                occurrence: $0,
                medicationName: medicationName,
                dosage: dosage,
                instructions: instructions,
                priority: priority
            )
        }
    }
}
