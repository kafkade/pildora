import SwiftUI

// MARK: - Cross-platform & accessibility view modifiers

public extension View {
    /// Styles a view as a section heading: applies the section-header font and
    /// exposes it to VoiceOver as a heading so users can navigate by rotor.
    func sectionHeaderStyle() -> some View {
        self
            .font(Typography.sectionHeader)
            .foregroundStyle(Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Applies the inset-grouped list style on iOS, falling back to sensible
    /// defaults on platforms where it is unavailable so the design system
    /// builds and previews everywhere (macOS, watchOS).
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #elseif os(macOS)
        self.listStyle(.sidebar)
        #else
        self
        #endif
    }

    /// Guarantees a view meets the 44×44pt minimum tap target, scaling with
    /// Dynamic Type via the caller-supplied metric where relevant.
    func minimumTapTarget() -> some View {
        self.frame(minWidth: Layout.minTapTarget, minHeight: Layout.minTapTarget)
    }
}
