import SwiftUI

/// Step 4 — The unrecoverable-data warning. A deliberate speed-bump: the user
/// must actively acknowledge that losing both the password and recovery key
/// means permanent data loss. This is the core trade-off of zero-knowledge.
struct WarningStepView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        OnboardingScaffold(
            icon: "exclamationmark.shield.fill",
            iconTint: Colors.warning,
            title: "There's no backdoor",
            subtitle: "Strong encryption means real privacy — and real responsibility."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                calloutRow(
                    icon: "person.badge.key.fill",
                    text: "Your master password and recovery key are the only ways into your vault."
                )
                calloutRow(
                    icon: "xmark.icloud.fill",
                    text: "Pildora never sees them. We cannot reset your password or recover your data for you."
                )
                calloutRow(
                    icon: "trash.slash.fill",
                    text: "If you lose both, your health data is gone permanently."
                )

                Toggle(isOn: $model.acknowledgedDataLoss) {
                    Text("I understand that Pildora cannot recover my data if I lose both my password and recovery key.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Colors.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: Colors.primary))
                .padding(.top, Theme.Spacing.sm)
                .accessibilityHint("Required before continuing")
            }
        } footer: {
            PildoraButton("I Understand", variant: .primary) { model.next() }
                .disabled(!model.acknowledgedDataLoss)
                .opacity(model.acknowledgedDataLoss ? 1 : 0.5)
        }
    }

    private func calloutRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Colors.warning)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
