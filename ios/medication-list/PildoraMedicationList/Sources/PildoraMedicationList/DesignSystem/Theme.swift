import SwiftUI

// MARK: - Theme (minimal design-token subset)

/// Minimal local subset of the full design system (#43). Provides semantic
/// color and spacing tokens so this feature is visually consistent and
/// dark-mode aware today, and can be replaced by the real design system later
/// without touching call sites that use `Theme`.
public enum Theme {

    // MARK: Spacing — 4pt / 8pt grid

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
    }

    // MARK: Semantic colors
    //
    // Uses system semantic colors so light/dark mode and high-contrast
    // accessibility settings are honored automatically.

    public enum Colors {
        public static let primary = Color.accentColor
        public static let surface = Color(uiColorName: .secondarySystemBackground)
        public static let surfaceElevated = Color(uiColorName: .tertiarySystemBackground)
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let success = Color.green
        public static let warning = Color.orange
        public static let error = Color.red
        public static let info = Color.blue
    }
}

// MARK: - Cross-platform semantic background colors

/// Names for platform-semantic background colors that exist on UIKit but not
/// on macOS AppKit. Mapped to sensible equivalents so the package builds and
/// previews on both platforms.
enum SemanticColorName {
    case secondarySystemBackground
    case tertiarySystemBackground
}

extension Color {
    init(uiColorName name: SemanticColorName) {
        #if canImport(UIKit)
        switch name {
        case .secondarySystemBackground:
            self = Color(uiColor: .secondarySystemBackground)
        case .tertiarySystemBackground:
            self = Color(uiColor: .tertiarySystemBackground)
        }
        #else
        // macOS fallback approximations for previews / `swift build`.
        switch name {
        case .secondarySystemBackground:
            self = Color.gray.opacity(0.12)
        case .tertiarySystemBackground:
            self = Color.gray.opacity(0.06)
        }
        #endif
    }
}
