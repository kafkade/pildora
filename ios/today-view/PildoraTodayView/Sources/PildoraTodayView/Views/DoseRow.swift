import SwiftUI
import PildoraDesignSystem

struct DoseRow: View {
    let item: TodayDoseItem
    let timeText: String
    let onMarkTaken: () -> Void

    @ScaledMetric(relativeTo: .body) private var confirmationButtonMinHeight: CGFloat = Layout.minTapTarget

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(item.dose.medicationName)
                        .font(Typography.cardTitle)
                        .foregroundStyle(titleColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Text(timeText)
                        .font(Typography.cardSubtitle)
                        .foregroundStyle(Colors.textSecondary)
                }

                Text(item.dose.dosage)
                    .font(Typography.cardSubtitle)
                    .foregroundStyle(Colors.textSecondary)

                HStack(spacing: Spacing.sm) {
                    DoseStatusBadge(state: item.state)
                    if item.state == .snoozed, let until = item.log?.snoozedUntil {
                        Text("until \(Self.timeFormatter.string(from: until))")
                            .font(Typography.caption)
                            .foregroundStyle(Colors.textSecondary)
                    } else if item.state == .skipped, let note = item.log?.note, !note.isEmpty {
                        Text(note)
                            .font(Typography.caption)
                            .foregroundStyle(Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            if isActionable {
                Button("Taken", action: onMarkTaken)
                    .buttonStyle(.borderedProminent)
                    .tint(Colors.success)
                    .controlSize(.small)
                    .frame(minHeight: confirmationButtonMinHeight)
                    .accessibilityLabel(
                        "Mark \(item.dose.medicationName) \(item.dose.dosage) as taken"
                    )
                    .accessibilityHint("Logs this dose as taken")
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Layout.minTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var isActionable: Bool {
        item.state != .taken && item.state != .skipped
    }

    private var accessibilitySummary: String {
        "\(item.dose.medicationName), \(item.dose.dosage), \(timeText), \(item.state.displayText)"
    }

    private var titleColor: Color {
        switch item.state {
        case .dueNow: return Colors.warning
        case .overdue: return Colors.error
        default: return Colors.textPrimary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
