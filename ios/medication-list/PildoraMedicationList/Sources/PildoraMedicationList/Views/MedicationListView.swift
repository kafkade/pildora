import SwiftUI
import PildoraDesignSystem

// MARK: - Medication List View

/// The primary medication list: a scrollable, category-grouped list of all
/// medications with search/filter by name, low-inventory indicators, and
/// navigation to per-medication detail. The toolbar links to the profile /
/// export screen.
public struct MedicationListView: View {
    @ObservedObject private var store: MedicationStore
    @State private var showingAddEditor = false
    @State private var pendingDeletion: Medication?

    public init(store: MedicationStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.medications.isEmpty {
                    emptyState
                } else if store.sections.isEmpty {
                    noResultsState
                } else {
                    list
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add medication")
                    }
                    .accessibilityIdentifier("add-medication-button")
                }
                ToolbarItem(placement: profileToolbarPlacement) {
                    NavigationLink {
                        ProfileView(store: store)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .accessibilityLabel("Profile and settings")
                    }
                }
            }
            .sheet(isPresented: $showingAddEditor) {
                MedicationEditorView(store: store)
            }
            .confirmationDialog(
                "Delete this medication?",
                isPresented: deletionBinding,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { medication in
                Button("Delete \(medication.name)", role: .destructive) {
                    store.deleteMedication(id: medication.id)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("This also removes its schedules, dose history, and inventory. This can't be undone.")
            }
        }
        .searchable(text: $store.searchText, prompt: "Search medications")
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var profileToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }

    private var list: some View {
        List {
            if !store.lowStockMedications.isEmpty {
                lowStockSummary
            }
            ForEach(store.sections) { section in
                Section {
                    ForEach(section.medications) { med in
                        NavigationLink {
                            MedicationDetailView(store: store, medicationID: med.id)
                        } label: {
                            MedicationRow(medication: med, inventory: store.inventory(for: med.id))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = med
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(section.category.displayName)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .groupedListStyle()
    }

    private var lowStockSummary: some View {
        Section {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityHidden(true)
                Text(lowStockSummaryText)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(lowStockSummaryText)
        }
    }

    private var lowStockSummaryText: String {
        let count = store.lowStockMedications.count
        return count == 1
            ? "1 medication is low and needs a refill"
            : "\(count) medications are low and need a refill"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Medications",
            systemImage: "pills",
            description: Text("Medications you add will appear here.")
        )
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: store.searchText)
    }
}

#if DEBUG
#Preview("List") {
    MedicationListView(store: .sample())
}

#Preview("List · Dark") {
    MedicationListView(store: .sample())
        .preferredColorScheme(.dark)
}

#Preview("List · xxxLarge") {
    MedicationListView(store: .sample())
        .environment(\.dynamicTypeSize, .xxxLarge)
}
#endif
