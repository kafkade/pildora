import SwiftUI

// MARK: - Typography

/// The Pildora type scale. Every token is built on a semantic
/// `Font.TextStyle`, so text scales with the user's preferred content size all
/// the way up to the accessibility sizes (`.accessibility1`…`.accessibility5`,
/// i.e. xxxLarge+) required by the project's large-text persona.
///
/// Never hard-code `.system(size:)`; reference these tokens so Dynamic Type is
/// preserved everywhere.
public enum Typography {
    /// Screen-level title (e.g. a large navigation title).
    public static let largeTitle: Font = .largeTitle.weight(.bold)
    /// A prominent section or page title.
    public static let title: Font = .title2.weight(.semibold)
    /// A grouped-content section header.
    public static let sectionHeader: Font = .title3.weight(.semibold)
    /// The title line of a card or list row.
    public static let cardTitle: Font = .headline
    /// A secondary line beneath a card/row title.
    public static let cardSubtitle: Font = .subheadline
    /// Default running text.
    public static let body: Font = .body
    /// Emphasized inline text.
    public static let bodyEmphasized: Font = .body.weight(.semibold)
    /// Supporting text, slightly smaller than body.
    public static let callout: Font = .callout
    /// Small print — timestamps, source attribution, badges.
    public static let caption: Font = .footnote
    /// Smallest supported text.
    public static let captionSmall: Font = .caption
}
