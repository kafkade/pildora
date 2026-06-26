import SwiftUI

// MARK: - Profile View

/// Profile screen: a low-stock overview, plus navigation to settings and data
/// export. Acts as the hub for app-level configuration and Doctor Mode export.
struct ProfileView: View {
    @ObservedObject var store: MedicationStore

    var body: some View {
        List {
            Section {
                summaryRow(
                    icon: "pills.fill",
                    title: "Tracked items",
                    value: "\(store.medications.count)"
                )
                summaryRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Low on stock",
                    value: "\(store.lowStockMedications.count)",
                    emphasize: !store.lowStockMedications.isEmpty
                )
            } header: {
                Text("Overview")
                    .accessibilityAddTraits(.isHeader)
            }

            Section {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                NavigationLink {
                    ExportView(store: store)
                } label: {
                    Label("Export data", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                Text(DrugReference.disclaimer)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text("Pildora is a tracking tool, not a source of medical advice.")
            }
        }
        .groupedListStyle()
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func summaryRow(icon: String, title: String, value: String, emphasize: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(emphasize ? Theme.Colors.warning : Theme.Colors.primary)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(value)
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(emphasize ? Theme.Colors.warning : Theme.Colors.textPrimary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        ProfileView(store: .sample())
    }
}
#endif
