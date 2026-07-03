import SwiftUI

/// Step 1 — Welcome. Introduces Pildora's zero-knowledge model up front so the
/// user understands the security trade-off before creating a password.
struct WelcomeStepView: View {
    @ObservedObject var model: OnboardingFlowModel

    private let points: [(icon: String, title: String, detail: String)] = [
        ("lock.shield.fill", "Encrypted on your device",
         "Your medications and health data are encrypted before they ever leave your iPhone."),
        ("eye.slash.fill", "Only you can read it",
         "Pildora is zero-knowledge — not even we can see your data. No accounts, no tracking, no selling."),
        ("iphone.and.arrow.forward", "Works offline",
         "Everything works without a connection. Optional sync is always end-to-end encrypted."),
    ]

    var body: some View {
        OnboardingScaffold(
            icon: "heart.text.square.fill",
            title: "Welcome to Pildora",
            subtitle: "A private, encrypted place to track your medications and supplements."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(points, id: \.title) { point in
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        Image(systemName: point.icon)
                            .font(.title2)
                            .foregroundStyle(Colors.primary)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(point.title)
                                .font(Theme.Typography.cardTitle)
                                .foregroundStyle(Colors.textPrimary)
                            Text(point.detail)
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Colors.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } footer: {
            PildoraButton("Get Started", variant: .primary) { model.next() }
                .accessibilityHint("Begins setting up your encrypted vault")
        }
    }
}
