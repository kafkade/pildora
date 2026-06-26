import Foundation

// MARK: - Export Models

/// Codable snapshot of all user data for a full decrypted JSON export.
///
/// This is the user's own data, exported on-device at their request. It is
/// **decrypted** by design (the export is for the user / their doctor) but is
/// never transmitted to a server by this package.
public struct ExportDocument: Codable, Equatable {
    public struct Meta: Codable, Equatable {
        public var app: String
        public var schemaVersion: Int
        public var exportedAt: Date
        public var vaultId: String
        public var disclaimer: String
    }

    public struct Entry: Codable, Equatable {
        public var medication: Medication
        public var inventory: InventoryRecord?
        public var reference: DrugReference?
    }

    public var meta: Meta
    public var medications: [Entry]
}

// MARK: - Data Exporter

/// Produces a full decrypted JSON export of the user's medication data.
public enum DataExporter {

    public static let schemaVersion = 1

    /// Build an `ExportDocument` from current store state.
    @MainActor
    public static func document(from store: MedicationStore, now: Date = Date()) -> ExportDocument {
        let entries = store.medications
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { med in
                ExportDocument.Entry(
                    medication: med,
                    inventory: store.inventory(for: med.id),
                    reference: store.reference(for: med)
                )
            }
        let vaultId = store.medications.first?.vaultId ?? "vault-default"
        return ExportDocument(
            meta: .init(
                app: "Pildora",
                schemaVersion: schemaVersion,
                exportedAt: now,
                vaultId: vaultId,
                disclaimer: DrugReference.disclaimer
            ),
            medications: entries
        )
    }

    /// Encode an export document to pretty-printed, sorted JSON data.
    public static func jsonData(for document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Convenience: JSON `String` for an export document.
    public static func jsonString(for document: ExportDocument) throws -> String {
        let data = try jsonData(for: document)
        return String(decoding: data, as: UTF8.self)
    }

    /// Suggested filename for a JSON export, e.g. `pildora-export-2026-06-26.json`.
    public static func suggestedFilename(now: Date = Date(), ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "pildora-export-\(f.string(from: now)).\(ext)"
    }
}
