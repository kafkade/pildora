import SwiftUI

// MARK: - Dose Confirmation View

struct DoseConfirmationView: View {
    let medication: SampleMedication
    let onDismiss: () -> Void

    @State private var snoozeMinutes = 15
    @State private var showSnoozeOptions = false
    @State private var skipReason = ""
    @State private var showSkipReason = false

    @ScaledMetric(relativeTo: .title) private var heroIconSize: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var buttonMinHeight: CGFloat = 52

    private let snoozeOptions = [5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero section: medication identity
                    medicationHeader

                    Divider()

                    // Dose details
                    doseDetails

                    Divider()

                    // Action buttons
                    actionButtons

                    // Skip reason (shown after tapping Skip)
                    if showSkipReason {
                        skipReasonSection
                    }

                    // Snooze picker (shown after tapping Snooze)
                    if showSnoozeOptions {
                        snoozePicker
                    }
                }
                .padding()
            }
            .navigationTitle("Confirm Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Medication Header

    private var medicationHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: formIcon)
                .font(.system(size: heroIconSize * 0.6))
                .foregroundStyle(.tint)
                .frame(width: heroIconSize, height: heroIconSize)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(medication.name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if let generic = medication.genericName {
                Text(generic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dose Details

    private var doseDetails: some View {
        VStack(spacing: 16) {
            DetailRow(
                icon: "pills",
                label: "Dosage",
                value: "\(medication.dosage) \(medication.form.rawValue)"
            )

            DetailRow(
                icon: "clock",
                label: "Schedule",
                value: medication.frequency
            )

            if let prescriber = medication.prescriber {
                DetailRow(
                    icon: "stethoscope",
                    label: "Prescriber",
                    value: prescriber
                )
            }

            if let inv = medication.inventoryDescription {
                DetailRow(
                    icon: "archivebox",
                    label: "Inventory",
                    value: inv,
                    isWarning: medication.isLowInventory
                )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary: Taken
            Button {
                onDismiss()
            } label: {
                Label("Taken", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: buttonMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Mark \(medication.name) \(medication.dosage) as taken")
            .accessibilityHint("Logs this dose as taken and returns to the medication list")

            HStack(spacing: 12) {
                // Snooze
                Button {
                    withAnimation {
                        showSnoozeOptions.toggle()
                        showSkipReason = false
                    }
                } label: {
                    Label("Snooze", systemImage: "bell.and.waves.left.and.right")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: buttonMinHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Snooze \(medication.name) reminder")
                .accessibilityHint(
                    showSnoozeOptions
                        ? "Closes snooze options"
                        : "Opens snooze duration picker"
                )

                // Skip
                Button {
                    withAnimation {
                        showSkipReason.toggle()
                        showSnoozeOptions = false
                    }
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: buttonMinHeight)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel("Skip \(medication.name) \(medication.dosage) dose")
                .accessibilityHint(
                    showSkipReason
                        ? "Closes skip reason field"
                        : "Opens a field to record why you are skipping this dose"
                )
            }
        }
    }

    // MARK: - Snooze Picker

    private var snoozePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snooze for:")
                .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)

            ForEach(snoozeOptions, id: \.self) { minutes in
                Button {
                    snoozeMinutes = minutes
                    onDismiss()
                } label: {
                    HStack {
                        Text(snoozeLabel(minutes))
                            .font(.body)
                        Spacer()
                        if minutes == snoozeMinutes {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Snooze \(medication.name) for \(snoozeLabel(minutes))"
                )
                .accessibilityAddTraits(
                    minutes == snoozeMinutes ? [.isSelected] : []
                )
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Skip Reason

    private var skipReasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason for skipping (optional):")
                .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)

            TextField("e.g., side effects, ran out", text: $skipReason)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .accessibilityLabel("Skip reason for \(medication.name)")

            Button {
                onDismiss()
            } label: {
                Text("Confirm Skip")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityLabel(
                "Confirm skipping \(medication.name) \(medication.dosage)"
            )
            .accessibilityHint(
                skipReason.isEmpty
                    ? "Skips dose without a reason"
                    : "Skips dose with reason: \(skipReason)"
            )
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var formIcon: String {
        switch medication.form {
        case .tablet: return "pills"
        case .capsule: return "capsule"
        case .liquid: return "drop.fill"
        case .injection: return "syringe"
        case .patch: return "bandage"
        case .drops: return "drop"
        }
    }

    private func snoozeLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        }
        return "1 hour"
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var isWarning: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isWarning ? .orange : .secondary)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(isWarning ? .orange : .primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Default") {
    DoseConfirmationView(
        medication: SampleData.currentDose,
        onDismiss: {}
    )
}

#Preview("xxxLarge") {
    DoseConfirmationView(
        medication: SampleData.currentDose,
        onDismiss: {}
    )
    .dynamicTypeSize(.xxxLarge)
}

#Preview("Accessibility 5") {
    DoseConfirmationView(
        medication: SampleData.currentDose,
        onDismiss: {}
    )
    .dynamicTypeSize(.accessibility5)
}

#Preview("Long Name — Accessibility 3") {
    DoseConfirmationView(
        medication: SampleData.medications[2],
        onDismiss: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
