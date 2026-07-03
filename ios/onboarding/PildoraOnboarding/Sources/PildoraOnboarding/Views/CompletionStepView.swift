import SwiftUI

/// Step 8 — Completion. Confirms setup succeeded and hands off to the app.
struct CompletionStepView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        OnboardingScaffold(
            icon: "checkmark.seal.fill",
            iconTint: Colors.success,
            title: "You're all set",
            subtitle: "Your encrypted vault is ready. Everything you add stays private on your device."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                summaryRow(icon: "lock.shield.fill", text: "Vault encrypted and protected by your master password.")
                if model.biometricUnlockEnabled {
                    summaryRow(icon: model.biometricKind.systemImage,
                               text: "\(model.biometricKind.displayName) unlock is on.")
                }
                summaryRow(icon: "doc.badge.gearshape.fill", text: "Keep your recovery kit somewhere safe.")
            }
        } footer: {
            PildoraButton("Start Using Pildora", variant: .primary) { model.next() }
        }
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Colors.success)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
