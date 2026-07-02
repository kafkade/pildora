import SwiftUI

// MARK: - Status Badge

/// Severity levels for a `StatusBadge`. Each level maps to a semantic color
/// **and** an SF Symbol, so status is never communicated by color alone — an
/// accessibility requirement (color-blind users, high-contrast mode).
public enum StatusLevel: Sendable, CaseIterable {
    case neutral
    case info
    case success
    case warning
    case error

    /// The semantic color token for this level.
    public var color: Color {
        switch self {
        case .neutral: return Colors.textSecondary
        case .info: return Colors.info
        case .success: return Colors.success
        case .warning: return Colors.warning
        case .error: return Colors.error
        }
    }

    /// The SF Symbol paired with this level.
    public var systemImage: String {
        switch self {
        case .neutral: return "circle"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }
}

/// A compact, labeled status indicator: icon + text + color (never color
/// alone). Combines into a single VoiceOver element so the label is announced
/// as one phrase.
public struct StatusBadge: View {
    private let text: String
    private let level: StatusLevel

    public init(_ text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: level.systemImage)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.caption.weight(.medium))
        }
        .foregroundStyle(level.color)
        .accessibilityElement(children: .combine)
    }
}
