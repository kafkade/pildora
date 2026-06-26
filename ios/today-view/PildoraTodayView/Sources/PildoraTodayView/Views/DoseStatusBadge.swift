import SwiftUI

struct DoseStatusBadge: View {
    let state: DoseState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(state.displayText)
                .font(.caption.weight(.semibold))
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
        case .upcoming: return .blue
        case .dueNow: return .orange
        case .overdue: return .red
        case .taken: return .green
        case .skipped: return .secondary
        case .snoozed: return .indigo
        }
    }
}
