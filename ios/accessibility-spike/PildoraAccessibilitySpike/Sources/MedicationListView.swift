import SwiftUI

// MARK: - Medication List View

struct MedicationListView: View {
    let medications: [SampleMedication]
    @State private var selectedMedication: SampleMedication?
    @State private var showDoseConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                // Urgent section: missed + due now
                let urgentMeds = medications.filter {
                    $0.lastDoseStatus == .missed || $0.lastDoseStatus == .due
                }
                if !urgentMeds.isEmpty {
                    Section {
                        ForEach(urgentMeds) { med in
                            MedicationCard(medication: med) {
                                selectedMedication = med
                                showDoseConfirmation = true
                            }
                        }
                    } header: {
                        Text("Needs Attention")
                            .accessibilityAddTraits(.isHeader)
                    }
                }

                // Upcoming section
                let upcomingMeds = medications.filter {
                    $0.lastDoseStatus == .upcoming
                }
                if !upcomingMeds.isEmpty {
                    Section {
                        ForEach(upcomingMeds) { med in
                            MedicationCard(medication: med) {
                                selectedMedication = med
                                showDoseConfirmation = true
                            }
                        }
                    } header: {
                        Text("Upcoming")
                            .accessibilityAddTraits(.isHeader)
                    }
                }

                // Completed section: taken + skipped
                let completedMeds = medications.filter {
                    $0.lastDoseStatus == .taken || $0.lastDoseStatus == .skipped
                }
                if !completedMeds.isEmpty {
                    Section {
                        ForEach(completedMeds) { med in
                            MedicationCard(medication: med) {
                                selectedMedication = med
                                showDoseConfirmation = true
                            }
                        }
                    } header: {
                        Text("Completed")
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .sheet(isPresented: $showDoseConfirmation) {
                if let med = selectedMedication {
                    DoseConfirmationView(medication: med) {
                        showDoseConfirmation = false
                    }
                }
            }
        }
    }
}

// MARK: - Medication Card

struct MedicationCard: View {
    let medication: SampleMedication
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 8

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Status icon
                statusIcon
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Medication name + dosage
                    HStack(alignment: .firstTextBaseline) {
                        Text(medication.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 4)

                        Text(medication.dosage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Form + frequency
                    Text("\(medication.form.rawValue.capitalized) · \(medication.frequency)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    // Status line (not color alone — includes text)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: badgeSize, height: badgeSize)
                            .accessibilityHidden(true)

                        Text(medication.statusDescription)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(statusColor)
                    }

                    // Inventory warning
                    if medication.isLowInventory, let inv = medication.inventoryDescription {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)

                            Text(inv)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(medication.accessibilityDescription)
        .accessibilityHint("Double tap to open dose confirmation")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch medication.lastDoseStatus {
        case .missed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        case .due:
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        case .taken:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        case .upcoming:
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.blue)
        }
    }

    private var statusColor: Color {
        switch medication.lastDoseStatus {
        case .missed: return .red
        case .due: return .orange
        case .taken: return .green
        case .skipped: return .secondary
        case .upcoming: return .blue
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Default Type Size") {
    MedicationListView(medications: SampleData.medications)
}

#Preview("xLarge Type Size") {
    MedicationListView(medications: SampleData.medications)
        .dynamicTypeSize(.xLarge)
}

#Preview("xxxLarge Type Size") {
    MedicationListView(medications: SampleData.medications)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Accessibility 3") {
    MedicationListView(medications: SampleData.medications)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Accessibility 5 (Maximum)") {
    MedicationListView(medications: SampleData.medications)
        .dynamicTypeSize(.accessibility5)
}
#endif
