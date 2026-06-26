import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct TodayView: View {
    @ObservedObject private var store: TodayStore

    public init(store: TodayStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !store.hasScheduledDoses {
                    noScheduleState
                } else if store.allScheduledDosesResolved {
                    allDoneState
                } else {
                    listContent
                }
            }
            .navigationTitle("Today")
        }
    }

    private var listContent: some View {
        List {
            prnSection

            ForEach(store.sections) { section in
                Section {
                    ForEach(section.doses) { item in
                        DoseRow(
                            item: item,
                            timeText: store.formattedTime(item.dose.scheduledAt),
                            onMarkTaken: {
                                markTaken(item)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                markTaken(item)
                            } label: {
                                Label("Taken", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)

                            Button {
                                skip(item)
                            } label: {
                                Label("Skip", systemImage: "forward.fill")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                snooze(item)
                            } label: {
                                Label("Snooze", systemImage: "zzz")
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    Text(section.window.displayName)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .platformListStyle()
    }

    private var prnSection: some View {
        Section {
            ForEach(store.prnMedications) { med in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(med.medicationName)
                            .font(.subheadline.weight(.medium))
                        Text("\(med.dosage) · As needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Log") {
                        logPRN(med.id)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Log PRN dose for \(med.medicationName)")
                }
                .frame(minHeight: 44)
            }

            if let latestPRN = store.prnHistoryToday.first {
                Text("Last PRN log: \(latestPRN.medicationName) at \(store.formattedTime(latestPRN.recordedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Last PRN log \(latestPRN.medicationName) at \(store.formattedTime(latestPRN.recordedAt))"
                    )
            }
        } header: {
            Text("Quick log (PRN)")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var noScheduleState: some View {
        ContentUnavailableView(
            "No doses scheduled",
            systemImage: "calendar.badge.clock",
            description: Text("Add a medication schedule to see today’s timeline.")
        )
    }

    private var allDoneState: some View {
        ContentUnavailableView(
            "All caught up",
            systemImage: "checkmark.circle.fill",
            description: Text("Great job — all scheduled doses for today are confirmed.")
        )
    }

    private func markTaken(_ item: TodayDoseItem) {
        store.markTaken(doseID: item.id)
        triggerSuccessHaptic()
    }

    private func skip(_ item: TodayDoseItem) {
        store.skipDose(doseID: item.id)
        triggerSelectionHaptic()
    }

    private func snooze(_ item: TodayDoseItem) {
        store.snoozeDose(doseID: item.id, minutes: 15)
        triggerSelectionHaptic()
    }

    private func logPRN(_ medicationID: String) {
        store.logPRN(medicationID: medicationID)
        triggerSelectionHaptic()
    }

    private func triggerSuccessHaptic() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

private extension View {
    @ViewBuilder
    func platformListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.automatic)
        #endif
    }
}

#if DEBUG
#Preview("Today") {
    TodayView(store: .sample())
}

#Preview("Today · xxxLarge") {
    TodayView(store: .sample())
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Today · Accessibility 3") {
    TodayView(store: .sample())
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
