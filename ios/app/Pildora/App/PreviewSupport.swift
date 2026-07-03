#if DEBUG
import Foundation
import PildoraDrugIndex
import PildoraDrugIndexLoader

/// Test/preview helpers for constructing a lightweight drug-index provider
/// without the full bootstrap (no vault, no network).
enum PreviewSupport {

    /// Build a core-only `TieredDrugIndexProvider` backed by a tiny throwaway
    /// index in a temporary directory. Suitable for SwiftUI previews.
    @MainActor
    static func makeDrugIndexProvider() throws -> TieredDrugIndexProvider {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-drug-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let coreURL = dir.appendingPathComponent("core-index.db")
        try DrugIndexBuilder.build(
            at: coreURL.path,
            drugs: [
                .init(preferredName: "Metformin", genericName: "metformin", rxcui: "6809",
                      brandNames: ["Glucophage"]),
                .init(preferredName: "Lisinopril", genericName: "lisinopril", rxcui: "29046",
                      brandNames: ["Zestril"]),
            ],
            supplements: [.init(name: "Vitamin D3", ingredients: ["cholecalciferol"])]
        )

        let store = try InstalledIndexStore(directory: dir.appendingPathComponent("store", isDirectory: true))
        return try TieredDrugIndexProvider(coreIndexURL: coreURL, store: store, downloader: nil)
    }
}
#endif
