import SwiftUI

// MARK: - Card

/// A rounded surface container that groups related content on a screen. Uses
/// the `surface` color token so it adapts to light/dark/high-contrast, and the
/// standard content padding + corner radius.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
