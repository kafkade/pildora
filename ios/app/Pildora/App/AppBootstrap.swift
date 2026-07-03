import Foundation
import PildoraDataLayer
import PildoraDrugIndexLoader
import PildoraMedicationList

/// Wires the app's runtime dependencies into a persistence-backed
/// `MedicationStore`: the encrypted vault database, the vault key, and the
/// tiered drug autocomplete index (bundled core + downloadable full).
enum AppBootstrap {

    /// The single default vault this slice operates on. Multi-vault selection is
    /// a later milestone; every row is still vault-scoped from day one.
    static let defaultVaultID = "default"

    /// Info.plist key holding the base URL for the full-index download. Empty ⇒
    /// core-only mode (no network).
    static let drugIndexBaseURLKey = "PildoraDrugIndexBaseURL"

    /// The wired-up result of bootstrapping.
    struct Bootstrapped {
        let store: MedicationStore
        /// The tiered autocomplete provider, exposed so the UI can observe the
        /// full-index download state and so callers can start the download.
        let drugIndex: TieredDrugIndexProvider
    }

    /// Build the fully wired app state. Runs on the main actor because both
    /// `MedicationStore` and `TieredDrugIndexProvider` are `@MainActor`-isolated.
    @MainActor
    static func bootstrap() throws -> Bootstrapped {
        // UI tests run against a clean, in-memory vault so each launch starts
        // from a known empty state, while still exercising the real on-device
        // core autocomplete index (core-only: no network in tests).
        if ProcessInfo.processInfo.arguments.contains("-uitesting") {
            let drugIndex = try makeDrugIndexProvider(allowDownload: false)
            let repository = InMemoryMedicationRepository(vaultID: defaultVaultID)
            let store = try MedicationStore(repository: repository, drugSuggester: drugIndex)
            return Bootstrapped(store: store, drugIndex: drugIndex)
        }

        let deriver = FFIDatabaseKeyDeriver()
        let manager = try VaultDatabaseManager(keyDeriver: deriver)

        let vaultKey = try VaultKeyStore.shared.loadOrCreateVaultKey(generate: { generateVaultKey() })

        let isFirstRun = !manager.databaseExists(vaultId: defaultVaultID)
        let database = try manager.open(vaultId: defaultVaultID, vaultKey: vaultKey)

        if isFirstRun {
            try database.insertVault(
                Vault(id: defaultVaultID, name: "Me", profileType: .personal)
            )
        }

        let repository = DatabaseMedicationRepository(database: database, vaultId: defaultVaultID)
        let drugIndex = try makeDrugIndexProvider(allowDownload: true)
        let store = try MedicationStore(repository: repository, drugSuggester: drugIndex)

        return Bootstrapped(store: store, drugIndex: drugIndex)
    }

    // MARK: Drug index

    /// Build the tiered drug-index provider over the bundled core index, wiring
    /// up the full-index downloader only when an endpoint is configured and
    /// `allowDownload` is true.
    @MainActor
    private static func makeDrugIndexProvider(allowDownload: Bool) throws -> TieredDrugIndexProvider {
        let coreIndexURL = try CoreDrugIndex.resolveCoreIndexURL()
        let store = try InstalledIndexStore()
        let downloader = allowDownload ? makeDownloader(store: store) : nil
        return try TieredDrugIndexProvider(
            coreIndexURL: coreIndexURL,
            store: store,
            downloader: downloader
        )
    }

    /// Construct the full-index downloader from the configured base URL, or
    /// `nil` when no (valid, non-empty) endpoint is set — keeping the app in
    /// core-only mode with no network access.
    private static func makeDownloader(store: InstalledIndexStore) -> FullIndexDownloader? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: drugIndexBaseURLKey) as? String,
            let baseURL = normalizedBaseURL(from: raw)
        else { return nil }

        return FullIndexDownloader(
            baseURL: baseURL,
            client: URLSessionDownloadClient(),
            store: store
        )
    }

    private static func normalizedBaseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Ensure a trailing slash so `manifest.json` / artifact filenames resolve
        // against the directory rather than replacing the last path component.
        let normalized = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        guard let url = URL(string: normalized), url.scheme != nil else { return nil }
        return url
    }
}
