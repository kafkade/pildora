import SwiftUI

// MARK: - Spacing

/// The Pildora spacing scale — a strict 4pt / 8pt grid used for all padding,
/// stack spacing, and insets so layout rhythm is consistent across screens.
///
/// Every value is a multiple of 4 (see `PildoraDesignSystemTests`), so mixing
/// tokens always keeps content aligned to the grid.
public enum Spacing {
    /// 2pt — hairline gaps between tightly-coupled elements (title / subtitle).
    public static let xxs: CGFloat = 2
    /// 4pt — the grid base unit.
    public static let xs: CGFloat = 4
    /// 8pt.
    public static let sm: CGFloat = 8
    /// 12pt.
    public static let md: CGFloat = 12
    /// 16pt — default content padding.
    public static let lg: CGFloat = 16
    /// 24pt.
    public static let xl: CGFloat = 24
    /// 32pt — section separation.
    public static let xxl: CGFloat = 32
}

// MARK: - Radius

/// Corner-radius tokens for surfaces and controls.
public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    /// Fully rounded (pill) — pass a large value and let SwiftUI clamp.
    public static let pill: CGFloat = 999
}

/// The minimum tap-target dimension (points). Apple's Human Interface
/// Guidelines require interactive elements to be at least 44×44pt.
public enum Layout {
    public static let minTapTarget: CGFloat = 44
}
