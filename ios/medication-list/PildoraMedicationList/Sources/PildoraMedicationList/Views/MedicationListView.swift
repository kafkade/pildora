import SwiftUI

// MARK: - Medication List View

/// The primary medication list: a scrollable, category-grouped list of all
/// medications with search/filter by name, low-inventory indicators, and
/// navigation to per-medication detail. The toolbar links to the profile /
/// export screen.
public struct MedicationListView: View {
    @ObservedObject private var store: MedicationStore

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
                    NavigationLink {
                        ProfileView(store: store)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .accessibilityLabel("Profile and settings")
                    }
                }
            }
        }
        .searchable(text: $store.searchText, prompt: "Search medications")
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
