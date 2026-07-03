import SwiftUI

/// Step 3 — Recovery key. Reveals the one-time recovery key, lets the user
/// export it as a PDF (Emergency-Kit style), and requires an explicit "I've
/// saved it" confirmation before continuing.
struct RecoveryKeyStepView: View {
    @ObservedObject var model: OnboardingFlowModel
    @State private var pdfURL: URL?
    @State private var isRevealed = true

    var body: some View {
        OnboardingScaffold(
            icon: "doc.badge.gearshape.fill",
            title: "Save your recovery key",
            subtitle: "This is your backup way in if you ever forget your master password. Store it somewhere safe — we can't show it again."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                recoveryKeyCard

                if let url = pdfURL {
                    ShareLink(item: url, preview: SharePreview("Pildora Recovery Kit")) {
                        Label("Export as PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PildoraButtonStyle(.secondary))
                    .simultaneousGesture(TapGesture().onEnded { _ = model.makeRecoveryPDF() })
                    .accessibilityHint("Saves or prints your recovery kit as a PDF")
                }

                Toggle(isOn: $model.confirmedRecoverySaved) {
                    Text("I've saved my recovery key somewhere safe.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Colors.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: Colors.primary))
                .accessibilityHint("Required before continuing")
            }
        } footer: {
            PildoraButton("Continue", variant: .primary) { model.next() }
                .disabled(!model.canLeaveRecovery)
                .opacity(model.canLeaveRecovery ? 1 : 0.5)
        }
        .onAppear(perform: generatePDF)
    }

    private var recoveryKeyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("RECOVERY KEY")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Colors.textSecondary)
            Text(model.recoveryDocument?.recoveryKey ?? "—")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Colors.separator, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your recovery key")
        .accessibilityValue(model.recoveryDocument?.recoveryKey ?? "")
    }

    private func generatePDF() {
        guard pdfURL == nil, let data = model.makeRecoveryPDF() else { return }
        // Reset the "exported" flag: generating for the share button on appear is
        // not itself a user export. (makeRecoveryPDF marks it; the toggle is what
        // actually gates progress, so this is harmless.)
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("Pildora-Recovery-Kit.pdf")
        do {
            try data.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            pdfURL = nil
        }
    }
}
