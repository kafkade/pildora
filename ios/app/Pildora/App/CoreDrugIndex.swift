import Foundation
import PildoraDrugIndex

/// Resolves the on-device **core** drug index that ships with the app.
///
/// The core index is the compact, offline tier of the tiered-loading design
/// (issue #68): a small, curated subset of the full openFDA / RxNorm corpus. The
/// full index is downloaded separately on first launch (see `AppBootstrap`).
///
/// Two ways the core index is produced, in priority order:
///  1. A **prebuilt** `core-index.db` bundled by the build-time generator
///     (`Scripts/generate-core-index.sh` → `pildora-core-index-tool`).
///  2. A fallback built at first launch from the bundled `core-seed.json`, so
///     the app still works even if the prebuilt artifact is absent.
///
/// This is public reference data — stored in plaintext by design and never mixed
/// with the encrypted vault database. Autocomplete queries run entirely against
/// this local file and never touch a server (zero-knowledge).
enum CoreDrugIndex {

    enum SeedError: Error, CustomStringConvertible {
        case missingBundledSeed
        var description: String {
            switch self {
            case .missingBundledSeed:
                return "core-seed.json is missing from the app bundle"
            }
        }
    }

    /// A URL to a ready-to-open core index database.
    ///
    /// Prefers a prebuilt `core-index.db` in the app bundle; otherwise builds one
    /// from the bundled `core-seed.json` into Application Support (once, then
    /// reused until the schema changes).
    static func resolveCoreIndexURL() throws -> URL {
        if let bundled = bundledPrebuiltIndexURL(), isUsable(at: bundled.path) {
            return bundled
        }
        return try buildFromBundledSeed()
    }

    // MARK: Prebuilt bundle artifact

    private static func bundledPrebuiltIndexURL() -> URL? {
        Bundle.main.url(forResource: "core-index", withExtension: "db")
    }

    private static func isUsable(at path: String) -> Bool {
        guard let index = try? DrugIndex(path: path, readonly: true) else { return false }
        return (try? index.schemaVersion()) == DrugIndexBuilder.schemaVersion
    }

    // MARK: First-launch fallback build

    private static func buildFromBundledSeed() throws -> URL {
        let target = try coreIndexURL()

        if !FileManager.default.fileExists(atPath: target.path) || !isUsable(at: target.path) {
            guard let seedURL = Bundle.main.url(forResource: "core-seed", withExtension: "json") else {
                throw SeedError.missingBundledSeed
            }
            try SeedIndexBuilder.build(fromSeedAt: seedURL, to: target.path)
        }
        return target
    }

    private static func coreIndexURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PildoraDrugIndex", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("core-index.db", isDirectory: false)
    }
}
