import SwiftUI

// MARK: - Source Tag

/// Renders a drug-reference attribution line, e.g.
/// `"Source: openFDA · Jan 12, 2026"`.
///
/// Per the project's data-boundary and disclaimer rules, every piece of
/// displayed drug reference data must show its source and date. Keeping this in
/// the design system ensures a consistent, accessible presentation everywhere
/// reference data appears.
public struct SourceTag: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Colors.textSecondary)
            .accessibilityLabel(text)
    }
}
