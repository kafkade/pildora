import SwiftUI

/// Step 6 — Optional iCloud Keychain backup of the device unlock key. This lets
/// the unlock key restore to a new device via iCloud Keychain (still protected
/// by the master password). It's off by default; the vault data itself is never
/// uploaded in plaintext.
struct ICloudBackupStepView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        OnboardingScaffold(
            icon: "key.icloud.fill",
            title: "Back up your unlock key",
            subtitle: "Optionally store this device's unlock key in your iCloud Keychain so you can restore access on a new device."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                infoRow(icon: "checkmark.shield.fill",
                        text: "Only the unlock key is backed up — your health data is never uploaded in plaintext.")
                infoRow(icon: "lock.fill",
                        text: "Protected by Apple's end-to-end encrypted iCloud Keychain and your master password.")
                infoRow(icon: "hand.raised.fill",
                        text: "Off by default. You stay in full control — turn it on only if you want it.")

                Toggle(isOn: $model.iCloudKeychainBackupEnabled) {
                    Text("Back up my unlock key to iCloud Keychain")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Colors.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: Colors.primary))
                .padding(.top, Theme.Spacing.sm)
            }
        } footer: {
            PildoraButton("Continue", variant: .primary) { model.next() }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Colors.primary)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
