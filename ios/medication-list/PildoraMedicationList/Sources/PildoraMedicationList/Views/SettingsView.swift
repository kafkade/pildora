import SwiftUI
import PildoraDesignSystem

// MARK: - Settings View

/// App settings surfaced on the profile screen: default refill threshold,
/// app-wide refill reminders toggle, and appearance preference.
struct SettingsView: View {
    @ObservedObject var store: MedicationStore

    var body: some View {
        Form {
            Section {
                Stepper(value: $store.settings.defaultRefillThreshold, in: 0...999) {
                    HStack {
                        Text("Default refill alert")
                        Spacer()
                        Text("\(store.settings.defaultRefillThreshold)")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .accessibilityLabel("Default refill alert threshold: \(store.settings.defaultRefillThreshold) units")

                Toggle("Refill reminders", isOn: $store.settings.refillRemindersEnabled)
                    .onChange(of: store.settings.refillRemindersEnabled) { _, _ in
                        store.reevaluateAllRefills()
                    }
            } header: {
                Text("Inventory")
            } footer: {
                Text("Refill reminders are delivered as local notifications only. Pildora never sends your medication or schedule data to a server.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $store.settings.preferredAppearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
