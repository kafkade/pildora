import Foundation

// MARK: - DosePriority

/// Priority tier for dose notifications. Higher-priority doses are scheduled
/// first when the pending queue approaches the iOS 64-notification ceiling, so a
/// power user never loses a life-sustaining medication reminder to a vitamin.
///
/// The tiers mirror the validated `notification-spike` strategy (issue #23).
///
/// > This is a timing/urgency hint for slot allocation only. It is **not** a
/// > clinical severity rating and provides no medical advice.
public enum DosePriority: Int, Comparable, CaseIterable, Codable, Sendable, CustomStringConvertible {
    /// Life-sustaining medications (e.g. insulin, immunosuppressants).
    case critical = 0
    /// Prescription medications (e.g. statins, blood-pressure meds).
    case high = 1
    /// OTC medications (e.g. aspirin, antacids).
    case normal = 2
    /// Supplements / vitamins (e.g. vitamin D, fish oil).
    case low = 3

    public static func < (lhs: DosePriority, rhs: DosePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .critical: return "critical"
        case .high: return "high"
        case .normal: return "normal"
        case .low: return "low"
        }
    }
}
