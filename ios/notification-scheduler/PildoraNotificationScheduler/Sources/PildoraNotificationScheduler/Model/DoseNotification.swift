import Foundation

// MARK: - DoseNotification

/// A single dose reminder to be materialized as a local notification.
///
/// This is the package's **neutral input model**. It carries exactly what the
/// planner needs to allocate a slot and what the content builder needs to render
/// a rich reminder — nothing more. It is intentionally decoupled from the
/// schedule engine's `DoseOccurrence` and the persisted `Schedule`; use
/// ``DoseNotification/init(occurrenceLike:medicationName:dosage:instructions:priority:)``
/// (see `DoseOccurrenceAdapter`) to build one from engine output until a later
/// wiring issue connects the two directly.
///
/// > Zero-knowledge: instances are computed on-device from local encrypted data
/// > and never leave the device. `instructions` is a user-entered passthrough —
/// > this package renders it verbatim and provides no medical advice.
public struct DoseNotification: Identifiable, Hashable, Sendable {
    /// Stable identifier for the persisted schedule this dose belongs to.
    public var scheduleId: String
    /// Identifier of the medication (or supplement) being dosed.
    public var medicationId: String
    /// Encryption-boundary the dose belongs to. Carried for multi-vault
    /// readiness even though notifications themselves are vault-agnostic.
    public var vaultId: String

    /// Display name of the medication/supplement (notification title).
    public var medicationName: String
    /// Human-readable dosage string (e.g. "500 mg", "2 tablets"). Optional.
    public var dosage: String?
    /// Optional special instructions (e.g. "Take with food"). Rendered verbatim.
    public var instructions: String?

    /// The absolute instant the dose is due.
    public var scheduledAt: Date
    /// Urgency tier used for slot allocation near the 64-notification ceiling.
    public var priority: DosePriority

    public init(
        scheduleId: String,
        medicationId: String,
        vaultId: String,
        medicationName: String,
        dosage: String? = nil,
        instructions: String? = nil,
        scheduledAt: Date,
        priority: DosePriority = .normal
    ) {
        self.scheduleId = scheduleId
        self.medicationId = medicationId
        self.vaultId = vaultId
        self.medicationName = medicationName
        self.dosage = dosage
        self.instructions = instructions
        self.scheduledAt = scheduledAt
        self.priority = priority
    }

    /// Deterministic identifier for the underlying notification request.
    ///
    /// Combines the schedule id with the whole-second due timestamp so the same
    /// dose maps to the same notification across replenishment cycles (making
    /// the "remove all → schedule fresh" rotation idempotent). Prefixed with
    /// ``DoseNotification/identifierPrefix`` so dose notifications can be
    /// distinguished from non-dose ones (refill/inventory/system alerts).
    public var id: String {
        let seconds = Int(scheduledAt.timeIntervalSince1970)
        return "\(Self.identifierPrefix)\(scheduleId)-\(seconds)"
    }

    /// Prefix on every dose-notification request identifier. Non-dose
    /// notifications (refill, inventory, system) must **not** use this prefix so
    /// rotation only ever clears/replaces dose notifications.
    public static let identifierPrefix = "dose-"
}

// MARK: - Slot ordering

extension DoseNotification: Comparable {
    /// Slot-allocation order: **soonest due time first**, then higher priority
    /// as a tiebreak for doses at the same instant, then a stable id tiebreak.
    ///
    /// Time-first ordering is a deliberate refinement over the
    /// `notification-spike`'s priority-first sort: taking the soonest N doses
    /// guarantees no imminent dose is ever starved by a far-future
    /// higher-priority one, so continuous replenishment delivers every dose
    /// within the coverage horizon on time. Priority still decides ties and
    /// which doses are dropped **at the horizon boundary** (the furthest-out
    /// doses), which is the correct place to prefer a critical medication over a
    /// vitamin.
    public static func < (lhs: DoseNotification, rhs: DoseNotification) -> Bool {
        if lhs.scheduledAt != rhs.scheduledAt {
            return lhs.scheduledAt < rhs.scheduledAt
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority // critical before low on ties
        }
        return lhs.id < rhs.id
    }
}
