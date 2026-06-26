import SwiftUI

// MARK: - Typography

/// Dynamic Type helpers. All text uses semantic `Font.TextStyle`s so it scales
/// with the user's preferred content size up to the accessibility (xxxLarge+)
/// sizes required by the project's accessibility persona.
public enum Typography {
    public static let cardTitle: Font = .headline
    public static let cardSubtitle: Font = .subheadline
    public static let body: Font = .body
    public static let caption: Font = .footnote
    public static let sectionHeader: Font = .title3.weight(.semibold)
}

public extension View {
    /// Marks a view as a heading for VoiceOver and applies the section header font.
    func sectionHeaderStyle() -> some View {
        self
            .font(Typography.sectionHeader)
            .accessibilityAddTraits(.isHeader)
    }
}
