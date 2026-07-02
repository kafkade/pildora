import SwiftUI
import PildoraDesignSystem

// MARK: - Root Feature View

/// Convenience entry point that wires a `MedicationStore` into the medication
/// list and re-evaluates refill reminders when the feature appears.
public struct MedicationFeatureView: View {
    @StateObject private var store: MedicationStore

    public init(store: @autoclosure @escaping () -> MedicationStore) {
        _store = StateObject(wrappedValue: store())
    }

    /// Sample-data entry point for previews / demos.
    public init() {
        _store = StateObject(wrappedValue: .sample())
    }

    public var body: some View {
        MedicationListView(store: store)
            .preferredColorScheme(colorScheme)
            .task { store.reevaluateAllRefills() }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.preferredAppearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Preview Catalog

#if DEBUG
/// A catalog of previews exercising Dynamic Type, dark mode, and key states —
/// used to visually verify accessibility requirements across the feature.
enum PreviewCatalog {}

#Preview("Feature · Default") {
    MedicationFeatureView()
}

#Preview("Feature · Dark") {
    MedicationFeatureView()
        .preferredColorScheme(.dark)
}

#Preview("Feature · Accessibility XL") {
    MedicationFeatureView()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Components") {
    List {
        Section("Status badges") {
            StatusBadge("Critical: 2 left", level: .error)
            StatusBadge("Low: 6 left", level: .warning)
            StatusBadge("Prescription", level: .info)
            StatusBadge("In stock", level: .success)
        }
        Section("Source tag") {
            SourceTag("Source: openFDA · Jan 12, 2026")
        }
    }
}
#endif
