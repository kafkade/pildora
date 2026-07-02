import SwiftUI
import PildoraDesignSystem

// MARK: - Medication Editor View

/// Add/edit form for a medication or supplement.
///
/// The name field drives live, debounced drug-name autocomplete against the
/// local FTS5 index (`store.drugSuggestions`). Picking a suggestion prefills the
/// generic name and RxNorm id and, for supplements, the category. Free-text
/// entry is always allowed, so supplements or items missing from the index can
/// still be added.
///
/// Zero-knowledge: autocomplete queries stay on-device; nothing is sent to a
/// server.
struct MedicationEditorView: View {
    @ObservedObject var store: MedicationStore
    @Environment(\.dismiss) private var dismiss

    /// The medication being edited, or `nil` when adding a new one.
    private let editingID: String?
    private let originalVaultID: String

    @State private var name: String
    @State private var genericName: String
    @State private var dosage: String
    @State private var form: MedicationForm
    @State private var category: MedicationCategory
    @State private var frequency: String
    @State private var prescriber: String
    @State private var notes: String
    @State private var rxnormId: String?
    @State private var drugReferenceId: String?

    @State private var suggestions: [DrugSuggestion] = []
    /// Set right after a suggestion is picked so the name change it causes does
    /// not immediately re-open the suggestion list.
    @State private var suppressNextSearch = false

    init(store: MedicationStore, editing medication: Medication? = nil) {
        self.store = store
        self.editingID = medication?.id
        self.originalVaultID = medication?.vaultId ?? store.activeVaultID
        _name = State(initialValue: medication?.name ?? "")
        _genericName = State(initialValue: medication?.genericName ?? "")
        _dosage = State(initialValue: medication?.dosage ?? "")
        _form = State(initialValue: medication?.form ?? .tablet)
        _category = State(initialValue: medication?.category ?? .prescription)
        _frequency = State(initialValue: medication?.frequency ?? "Once daily")
        _prescriber = State(initialValue: medication?.prescriber ?? "")
        _notes = State(initialValue: medication?.notes ?? "")
        _rxnormId = State(initialValue: medication?.rxnormId)
        _drugReferenceId = State(initialValue: medication?.drugReferenceId)
    }

    private var isEditing: Bool { editingID != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                detailsSection
                prescriptionSection
                notesSection
            }
            .navigationTitle(isEditing ? "Edit Medication" : "Add Medication")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-medication-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("save-medication-button")
                }
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalizationIfAvailable()
                .accessibilityIdentifier("medication-name-field")
                .task(id: name) { await refreshSuggestions() }

            ForEach(suggestions) { suggestion in
                Button {
                    apply(suggestion)
                } label: {
                    suggestionRow(suggestion)
                }
                .accessibilityIdentifier("suggestion-\(suggestion.id)")
            }
        } header: {
            Text("Medication")
        } footer: {
            if store.supportsDrugSuggestions {
                Text("Start typing to search the on-device drug list. Not finding it? Just keep typing — free-text names are fine for supplements.")
            }
        }
    }

    private func suggestionRow(_ suggestion: DrugSuggestion) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: suggestion.kind == .supplement ? "leaf" : "pills")
                .foregroundStyle(Theme.Colors.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(suggestion.displayName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Dosage (e.g. 50 mg)", text: $dosage)
                .accessibilityIdentifier("medication-dosage-field")

            Picker("Form", selection: $form) {
                ForEach(MedicationForm.allCases, id: \.self) { form in
                    Text(form.displayName).tag(form)
                }
            }
            .accessibilityIdentifier("medication-form-picker")

            Picker("Category", selection: $category) {
                ForEach(MedicationCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .accessibilityIdentifier("medication-category-picker")

            TextField("Frequency (e.g. Once daily)", text: $frequency)
                .accessibilityIdentifier("medication-frequency-field")
        }
    }

    private var prescriptionSection: some View {
        Section("Prescription") {
            TextField("Generic name (optional)", text: $genericName)
            TextField("Prescriber (optional)", text: $prescriber)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(1 ... 4)
                .accessibilityIdentifier("medication-notes-field")
        }
    }

    // MARK: Behavior

    private func refreshSuggestions() async {
        if suppressNextSearch {
            suppressNextSearch = false
            return
        }
        // Debounce: coalesce rapid keystrokes before hitting the index.
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        suggestions = await store.drugSuggestions(matching: name)
    }

    private func apply(_ suggestion: DrugSuggestion) {
        suppressNextSearch = true
        name = suggestion.displayName
        if let generic = suggestion.genericName { genericName = generic }
        rxnormId = suggestion.rxcui
        if suggestion.kind == .supplement { category = .supplement }
        suggestions = []
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGeneric = genericName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrescriber = prescriber.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingID, let existing = store.medications.first(where: { $0.id == editingID }) {
            var updated = existing
            updated.name = trimmedName
            updated.genericName = trimmedGeneric.isEmpty ? nil : trimmedGeneric
            updated.dosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.form = form
            updated.category = category
            updated.frequency = frequency.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.prescriber = trimmedPrescriber.isEmpty ? nil : trimmedPrescriber
            updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            updated.rxnormId = rxnormId
            updated.drugReferenceId = drugReferenceId
            store.updateMedication(updated)
        } else {
            let new = Medication(
                vaultId: originalVaultID,
                name: trimmedName,
                genericName: trimmedGeneric.isEmpty ? nil : trimmedGeneric,
                dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                form: form,
                category: category,
                frequency: frequency.trimmingCharacters(in: .whitespacesAndNewlines),
                prescriber: trimmedPrescriber.isEmpty ? nil : trimmedPrescriber,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                rxnormId: rxnormId,
                drugReferenceId: drugReferenceId
            )
            store.addMedication(new)
        }

        if store.lastError == nil { dismiss() }
    }
}

// MARK: - Platform helpers

private extension View {
    /// Words-capitalization on iOS; no-op elsewhere so the package builds on macOS.
    @ViewBuilder
    func textInputAutocapitalizationIfAvailable() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }
}

#if DEBUG
#Preview("Add") {
    MedicationEditorView(store: .sample())
}

#Preview("Edit") {
    MedicationEditorView(store: .sample(), editing: SampleData.medications[1])
}
#endif
