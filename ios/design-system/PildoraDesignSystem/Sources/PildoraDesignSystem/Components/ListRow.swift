import SwiftUI

// MARK: - List Row

/// A leading-icon / title / subtitle / trailing-detail row for use inside
/// lists. Enforces the 44pt minimum row height and combines the text into a
/// single VoiceOver element while leaving the trailing accessory separately
/// focusable.
public struct ListRow<Trailing: View>: View {
    private let systemImage: String?
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(
        systemImage: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Colors.primary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.sm)
            trailing
        }
        .frame(minHeight: Layout.minTapTarget)
    }
}
