import SwiftUI

/// A consistent layout shell for every onboarding step: a scrolling header
/// (icon + title + subtitle) above step-specific content, with a pinned footer
/// for the primary/secondary actions.
///
/// Centralizing the layout keeps spacing, Dynamic Type behavior, and VoiceOver
/// grouping identical across all steps.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        icon: String,
        iconTint: Color = Colors.primary,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    content()
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: Theme.Spacing.sm) {
                footer()
            }
            .padding(Theme.Spacing.lg)
            .background(Colors.background)
        }
        .background(Colors.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// An inline, dismissible error banner used by steps that can fail.
struct OnboardingErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Colors.error)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.Typography.callout)
                .foregroundStyle(Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Colors.error.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
