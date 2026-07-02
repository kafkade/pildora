import SwiftUI

// MARK: - TextField

/// A labeled text field with consistent surface styling, an optional leading
/// icon, and an optional inline error message. The visible label doubles as the
/// VoiceOver label, and the error is announced when present.
public struct PildoraTextField: View {
    private let title: String
    private let placeholder: String
    private let systemImage: String?
    private let isSecure: Bool
    private let errorMessage: String?
    @Binding private var text: String

    public init(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        systemImage: String? = nil,
        isSecure: Bool = false,
        errorMessage: String? = nil
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.isSecure = isSecure
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(Colors.textSecondary)

            HStack(spacing: Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                field
                    .font(Typography.body)
                    .foregroundStyle(Colors.textPrimary)
            }
            .padding(Spacing.md)
            .frame(minHeight: Layout.minTapTarget)
            .background(Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(errorMessage == nil ? Color.clear : Colors.error, lineWidth: 1.5)
            )

            if let errorMessage {
                StatusBadge(errorMessage, level: .error)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(text.isEmpty ? placeholder : text)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}
