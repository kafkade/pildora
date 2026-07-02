import SwiftUI

// MARK: - Button

/// Visual variants for `PildoraButton` / `PildoraButtonStyle`.
public enum PildoraButtonVariant: Sendable {
    /// High-emphasis, filled with the brand color. One per view, ideally.
    case primary
    /// Medium-emphasis, tinted outline.
    case secondary
    /// Destructive actions (delete, remove).
    case destructive

    var foreground: Color {
        switch self {
        case .primary: return Colors.onPrimary
        case .secondary: return Colors.primary
        case .destructive: return Colors.onPrimary
        }
    }

    var background: Color {
        switch self {
        case .primary: return Colors.primary
        case .secondary: return .clear
        case .destructive: return Colors.error
        }
    }

    var border: Color {
        switch self {
        case .primary: return .clear
        case .secondary: return Colors.primary
        case .destructive: return .clear
        }
    }
}

/// The shared button style. Enforces the 44pt minimum tap target, scales its
/// padding with Dynamic Type, and dims on press. Apply directly to any
/// `Button` via `.buttonStyle(PildoraButtonStyle(.primary))`.
public struct PildoraButtonStyle: ButtonStyle {
    private let variant: PildoraButtonVariant
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = Layout.minTapTarget

    public init(_ variant: PildoraButtonVariant) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyEmphasized)
            .foregroundStyle(variant.foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, Spacing.lg)
            .background(variant.background)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(variant.border, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A convenience button that renders a text label with a `PildoraButtonStyle`.
///
/// ```swift
/// PildoraButton("Save", variant: .primary) { save() }
/// ```
public struct PildoraButton: View {
    private let title: String
    private let systemImage: String?
    private let variant: PildoraButtonVariant
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: PildoraButtonVariant = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PildoraButtonStyle(variant))
    }
}
