import SwiftUI

// MARK: - Theme umbrella

/// A convenience umbrella that groups the design-system token namespaces under
/// a single entry point. Both forms are equivalent — use whichever reads best:
///
/// ```swift
/// .padding(Theme.Spacing.lg)      // grouped
/// .padding(Spacing.lg)            // direct
/// .foregroundStyle(Theme.Colors.textSecondary)
/// ```
public enum Theme {
    public typealias Spacing = PildoraDesignSystem.Spacing
    public typealias Radius = PildoraDesignSystem.Radius
    public typealias Layout = PildoraDesignSystem.Layout
    public typealias Colors = PildoraDesignSystem.Colors
    public typealias Typography = PildoraDesignSystem.Typography
}
