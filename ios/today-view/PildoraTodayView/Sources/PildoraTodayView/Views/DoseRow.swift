import SwiftUI

struct DoseRow: View {
    let item: TodayDoseItem
    let timeText: String
    let onMarkTaken: () -> Void

    @ScaledMetric(relativeTo: .body) private var confirmationButtonMinHeight: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.dose.medicationName)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(item.dose.dosage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    DoseStatusBadge(state: item.state)
                    if item.state == .snoozed, let until = item.log?.snoozedUntil {
                        Text("until \(Self.timeFormatter.string(from: until))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if item.state == .skipped, let note = item.log?.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if isActionable {
                Button("Taken", action: onMarkTaken)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .frame(minHeight: confirmationButtonMinHeight)
                    .accessibilityLabel(
                        "Mark \(item.dose.medicationName) \(item.dose.dosage) as taken"
                    )
                    .accessibilityHint("Logs this dose as taken")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
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
        case .dueNow: return .orange
        case .overdue: return .red
        default: return .primary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
