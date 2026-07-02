import SwiftUI
import PildoraDesignSystem

/// A dose-specific status badge. Its states are richer than the design
/// system's generic `StatusLevel`, but it draws from the same semantic color
/// tokens so it stays visually consistent with the rest of the app and adapts
/// to dark mode / high-contrast automatically.
struct DoseStatusBadge: View {
    let state: DoseState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: iconName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(state.displayText)
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch state {
        case .upcoming: return "clock"
        case .dueNow: return "bell.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .snoozed: return "zzz"
        }
    }

    private var color: Color {
        switch state {
        case .upcoming: return Colors.info
        case .dueNow: return Colors.warning
        case .overdue: return Colors.error
        case .taken: return Colors.success
        case .skipped: return Colors.textSecondary
        case .snoozed: return .indigo
        }
    }
}
