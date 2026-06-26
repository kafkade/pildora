import SwiftUI

// MARK: - Base Components (minimal design-system subset)

/// A rounded surface container used to group related content.
public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

// MARK: - Status Badge

/// Severity levels for a `StatusBadge`. Each carries text *and* an icon, so
/// status is never communicated by color alone (accessibility requirement).
public enum StatusLevel: Sendable {
    case neutral
    case info
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .neutral: return Theme.Colors.textSecondary
        case .info: return Theme.Colors.info
        case .success: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .error: return Theme.Colors.error
        }
    }

    var systemImage: String {
        switch self {
        case .neutral: return "circle"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }
}

/// A compact labeled status indicator. Text + icon + color, never color alone.
public struct StatusBadge: View {
    private let text: String
    private let level: StatusLevel

    public init(_ text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: level.systemImage)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.caption.weight(.medium))
        }
        .foregroundStyle(level.color)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - List Row

/// A leading-icon / title / trailing-detail row used in lists.
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
        HStack(spacing: Theme.Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.primary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            trailing
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Source Tag

/// Renders a drug-reference attribution line ("Source: openFDA · Jan 12, 2026").
/// Required on every piece of displayed drug reference data.
public struct SourceTag: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel(text)
    }
}
