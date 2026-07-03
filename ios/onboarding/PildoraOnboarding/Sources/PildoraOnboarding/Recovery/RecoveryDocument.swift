import Foundation

// MARK: - Recovery document content

/// A platform-independent description of the printable recovery sheet — the
/// Pildora equivalent of the 1Password Emergency Kit.
///
/// Building the content is separated from PDF rendering so the text (including
/// the critical warnings) is unit-testable on any platform, and the actual PDF
/// is produced only where UIKit is available.
public struct RecoveryDocument: Equatable, Sendable {
    /// The product name printed at the top.
    public let appName: String
    /// Sheet title (e.g. "Recovery Kit").
    public let title: String
    /// The name of the vault this kit recovers.
    public let vaultName: String
    /// The formatted recovery key, shown in a boxed monospace block.
    public let recoveryKey: String
    /// When the kit was generated, already formatted for display.
    public let generatedOn: String
    /// Numbered "what this is / how to use it" instructions.
    public let instructions: [String]
    /// The unrecoverable-data warning. Printed prominently.
    public let warning: String

    public init(
        appName: String = "Pildora",
        title: String = "Recovery Kit",
        vaultName: String,
        recoveryKey: String,
        generatedOn: String,
        instructions: [String],
        warning: String
    ) {
        self.appName = appName
        self.title = title
        self.vaultName = vaultName
        self.recoveryKey = recoveryKey
        self.generatedOn = generatedOn
        self.instructions = instructions
        self.warning = warning
    }

    /// Build the standard recovery kit for a vault + recovery key.
    public static func standard(
        vaultName: String,
        recoveryKey: String,
        now: Date = Date()
    ) -> RecoveryDocument {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return RecoveryDocument(
            vaultName: vaultName,
            recoveryKey: recoveryKey,
            generatedOn: formatter.string(from: now),
            instructions: [
                "This Recovery Kit lets you regain access to your Pildora vault if you forget your master password.",
                "Print this page or save the PDF somewhere safe and offline — a locked drawer or a fireproof box. Do not store it in the same place as your device.",
                "Anyone with this recovery key AND access to your data could unlock your vault, so keep it private.",
                "Pildora never sees your master password or this recovery key. We cannot reset or recover them for you.",
            ],
            warning: "If you lose BOTH your master password and this recovery key, your health data is permanently unrecoverable. There is no backdoor and no reset."
        )
    }

    /// A plain-text rendering — the fallback share format when PDF rendering is
    /// unavailable, and the basis for tests.
    public var plainText: String {
        var lines: [String] = []
        lines.append("\(appName) — \(title)")
        lines.append("Vault: \(vaultName)")
        lines.append("Generated \(generatedOn)")
        lines.append("")
        lines.append("RECOVERY KEY")
        lines.append(recoveryKey)
        lines.append("")
        for (index, step) in instructions.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        lines.append("")
        lines.append("⚠︎ \(warning)")
        return lines.joined(separator: "\n")
    }

    /// A suggested file name for exports (no path, no extension).
    public var suggestedFileName: String {
        "Pildora-Recovery-Kit"
    }
}
