import SwiftUI

// MARK: - Inventory Editor View

/// Manual inventory controls for a medication: current count stepper, a
/// user-configurable refill threshold, a refill-reminder toggle, and a
/// "Record refill" action. Embedded as a section in the detail screen.
struct InventoryEditorView: View {
    @ObservedObject var store: MedicationStore
    let medicationID: String
    let unitNoun: String

    @State private var showRecordRefill = false
    @State private var refillAmount = 30

    private var inventory: InventoryRecord? { store.inventory(for: medicationID) }

    var body: some View {
        Section {
            countStepper
            thresholdStepper
            reminderToggle
            recordRefillButton
        } header: {
            Text("Inventory")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            if let inventory, inventory.isLow {
                Label(
                    inventory.isCritical
                        ? "Critically low — refill soon."
                        : "Low stock — consider a refill.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Typography.caption)
                .foregroundStyle(inventory.isCritical ? Theme.Colors.error : Theme.Colors.warning)
            }
        }
        .alert("Record refill", isPresented: $showRecordRefill) {
            TextField("New count", value: $refillAmount, format: .number)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                store.recordRefill(newCount: refillAmount, for: medicationID)
            }
        } message: {
            Text("Set the total \(unitNoun) count after refilling.")
        }
    }

    private var countStepper: some View {
        let count = inventory?.currentCount ?? 0
        return Stepper(
            value: Binding(
                get: { inventory?.currentCount ?? 0 },
                set: { store.setInventoryCount($0, for: medicationID) }
            ),
            in: 0...9999
        ) {
            HStack {
                Text("On hand")
                Spacer()
                Text("\(count) \(count == 1 ? unitNoun : "\(unitNoun)s")")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityLabel("On hand: \(count) \(unitNoun)")
    }

    private var thresholdStepper: some View {
        let threshold = inventory?.refillThreshold ?? store.settings.defaultRefillThreshold
        return Stepper(
            value: Binding(
                get: { inventory?.refillThreshold ?? store.settings.defaultRefillThreshold },
                set: { store.setRefillThreshold($0, for: medicationID) }
            ),
            in: 0...999
        ) {
            HStack {
                Text("Refill alert at")
                Spacer()
                Text("\(threshold) \(threshold == 1 ? unitNoun : "\(unitNoun)s")")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityLabel("Refill alert threshold: \(threshold) \(unitNoun)")
    }

    private var reminderToggle: some View {
        Toggle(
            "Refill reminder",
            isOn: Binding(
                get: { inventory?.refillReminderEnabled ?? false },
                set: { store.setRefillReminderEnabled($0, for: medicationID) }
            )
        )
        .disabled(inventory == nil)
    }

    private var recordRefillButton: some View {
        Button {
            refillAmount = max(inventory?.refillThreshold ?? 30, 30)
            showRecordRefill = true
        } label: {
            Label("Record refill", systemImage: "arrow.clockwise")
        }
    }
}
