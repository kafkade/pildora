import SwiftUI
import PildoraDesignSystem

// MARK: - Export View

/// Data export screen. Generates a full **decrypted JSON** export of all user
/// data and a **Doctor Mode PDF** summary — both produced entirely on-device.
/// Files are shared via the system share sheet (`ShareLink`); nothing is sent
/// to a server.
struct ExportView: View {
    @ObservedObject var store: MedicationStore

    @State private var jsonURL: URL?
    @State private var pdfURL: URL?
    @State private var jsonPreview: String = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if let jsonURL {
                    ShareLink(item: jsonURL) {
                        Label("Export full data (JSON)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("Preparing JSON…", systemImage: "hourglass")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Export summary (PDF · Doctor Mode)", systemImage: "doc.richtext")
                    }
                } else {
                    Label("Preparing PDF…", systemImage: "hourglass")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } header: {
                Text("Export")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Exports are generated on your device. Pildora does not upload your data. The JSON export is decrypted — store it somewhere safe.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Colors.error)
                }
            }

            if !jsonPreview.isEmpty {
                Section("JSON preview") {
                    Text(jsonPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel("JSON export preview")
                }
            }
        }
        .navigationTitle("Export")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await prepareExports() }
    }

    private func prepareExports() async {
        let document = DataExporter.document(from: store)
        do {
            let jsonData = try DataExporter.jsonData(for: document)
            jsonPreview = String(decoding: jsonData.prefix(2000), as: UTF8.self)
            jsonURL = try writeTemp(
                data: jsonData,
                filename: DataExporter.suggestedFilename(ext: "json")
            )

            let report = DoctorReport.build(from: store)
            let pdfData = PDFReportRenderer.render(report)
            // On non-UIKit platforms this is plain text; keep the extension honest.
            let pdfExt = pdfData.starts(with: Array("%PDF".utf8)) ? "pdf" : "txt"
            pdfURL = try writeTemp(
                data: pdfData,
                filename: DataExporter.suggestedFilename(ext: pdfExt)
            )
        } catch {
            errorMessage = "Could not prepare export: \(error.localizedDescription)"
        }
    }

    private func writeTemp(data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
