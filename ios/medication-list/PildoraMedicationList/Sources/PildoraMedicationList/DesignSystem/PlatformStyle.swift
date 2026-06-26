import SwiftUI

// MARK: - Cross-platform list styling

extension View {
    /// Applies the inset-grouped list style on iOS, falling back to a sensible
    /// default on platforms (macOS) where it is unavailable, so the package
    /// builds and previews everywhere.
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.sidebar)
        #endif
    }
}
