import SwiftUI

// MARK: - Medication Detail View

/// Detail screen for a single medication: header (name, dosage, form,
/// frequency, prescriber/notes), inventory editor, and the drug reference
/// section with source attribution and disclaimer.
struct MedicationDetailView: View {
    @ObservedObject var store: MedicationStore
    let medicationID: String

    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    private var medication: Medication? {
        store.medications.first { $0.id == medicationID }
    }

    var body: some View {
        Group {
            if let medication {
                List {
                    headerSection(medication)
                    InventoryEditorView(
                        store: store,
                        medicationID: medication.id,
                        unitNoun: medication.form.unitNoun
                    )
                    DrugReferenceSection(reference: store.reference(for: medication))
                    deleteSection(medication)
                }
                .groupedListStyle()
                .navigationTitle(medication.name)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showingEditor = true }
                            .accessibilityIdentifier("edit-medication-button")
                    }
                }
                .sheet(isPresented: $showingEditor) {
                    MedicationEditorView(store: store, editing: medication)
                }
                .confirmationDialog(
                    "Delete \(medication.name)?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.deleteMedication(id: medication.id)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This also removes its schedules, dose history, and inventory. This can't be undone.")
                }
            } else {
                ContentUnavailableView("Medication not found", systemImage: "pills")
            }
        }
    }

    private func deleteSection(_ medication: Medication) -> some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Medication", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("delete-medication-button")
        }
    }

    private func headerSection(_ medication: Medication) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(medication.titleWithDosage)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                StatusBadge(medication.category.displayName, level: .info)

                detailRow(label: "Form", value: medication.form.displayName)
                detailRow(label: "Frequency", value: medication.frequency)
                if let generic = medication.genericName {
                    detailRow(label: "Generic", value: generic)
                }
                if let prescriber = medication.prescriber {
                    detailRow(label: "Prescriber", value: prescriber)
                }
                if let notes = medication.notes, !notes.isEmpty {
                    detailRow(label: "Notes", value: notes)
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.md)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#if DEBUG
#Preview("Detail") {
    NavigationStack {
        MedicationDetailView(store: .sample(), medicationID: "med-2")
    }
}

#Preview("Detail · Low stock") {
    NavigationStack {
        MedicationDetailView(store: .sample(), medicationID: "med-4")
    }
}
#endif
