import Foundation
import PildoraDataLayer
import PildoraDrugIndexLoader
import PildoraMedicationList
import PildoraOnboarding

/// Wires the app's runtime dependencies together and gates first launch on the
/// onboarding flow.
///
/// On first run (`needsOnboarding()` is true) the app presents
/// ``PildoraOnboarding``'s flow, which derives the master key, creates the vault
/// key, and stores it in the Keychain. Thereafter the app opens the existing
/// encrypted vault directly.
enum AppBootstrap {

    /// The single default vault this slice operates on. Multi-vault selection is
    /// a later milestone; every row is still vault-scoped from day one.
    static let defaultVaultID = "default"

    /// Info.plist key holding the base URL for the full-index download. Empty ⇒
    /// core-only mode (no network).
    static let drugIndexBaseURLKey = "PildoraDrugIndexBaseURL"

    /// Persists onboarding progress (resume) and the completed vault config.
    static let onboardingStore = UserDefaultsOnboardingStateStore()

    /// The wired-up result of bootstrapping.
    struct Bootstrapped {
        let store: MedicationStore
        /// The tiered autocomplete provider, exposed so the UI can observe the
        /// full-index download state and so callers can start the download.
        let drugIndex: TieredDrugIndexProvider
    }

    enum BootstrapError: Error {
        /// Onboarding reported complete but no vault key is in the Keychain.
        case missingVaultKey
    }

    /// Whether the app is running under UI tests (clean, in-memory, no onboarding).
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
    }

    /// Whether first-run onboarding must be shown: onboarding is incomplete or
    /// its vault key is missing from the Keychain.
    static func needsOnboarding() -> Bool {
        guard onboardingStore.isOnboardingComplete else { return true }
        return !VaultKeyStore.shared.hasKey()
    }

    // MARK: In-memory (UI tests)

    /// A clean, in-memory vault so each UI-test launch starts from a known empty
    /// state, while still exercising the real on-device core autocomplete index.
    @MainActor
    static func makeUITestingBootstrap() throws -> Bootstrapped {
        let drugIndex = try makeDrugIndexProvider(allowDownload: false)
        let repository = InMemoryMedicationRepository(vaultID: defaultVaultID)
        let store = try MedicationStore(repository: repository, drugSuggester: drugIndex)
        return Bootstrapped(store: store, drugIndex: drugIndex)
    }

    // MARK: Open an existing vault

    /// Open the already-configured encrypted vault, reading its key from the
    /// Keychain (which may prompt for biometrics if the user enabled it).
    @MainActor
    static func openVault() throws -> Bootstrapped {
        guard let vaultKey = try VaultKeyStore.shared.load() else {
            throw BootstrapError.missingVaultKey
        }
        let manager = try VaultDatabaseManager(keyDeriver: FFIDatabaseKeyDeriver())
        let database = try manager.open(vaultId: defaultVaultID, vaultKey: vaultKey)
        return try wire(database: database)
    }

    // MARK: Onboarding

    /// Build the onboarding flow model, wiring its completion hooks to store the
    /// vault key, seed the vault (+ optional first medication), and hand the
    /// ready app state back to `onReady` when the user leaves the success screen.
    @MainActor
    static func makeOnboardingModel(
        onReady: @escaping (Bootstrapped) -> Void
    ) -> OnboardingFlowModel {
        // Holds the vault opened during commit so the success screen can hand it
        // off without re-reading (and re-prompting) the Keychain.
        final class Ready { var bootstrapped: Bootstrapped? }
        let ready = Ready()

        return OnboardingFlowModel(
            crypto: FFIOnboardingCrypto(),
            store: onboardingStore,
            biometrics: LocalAuthenticationBiometrics(),
            vaultID: defaultVaultID,
            vaultName: "Me",
            onComplete: { result in
                try VaultKeyStore.shared.save(
                    result.vaultKey,
                    biometricProtected: result.biometricUnlockEnabled,
                    synchronizable: result.iCloudKeychainBackupEnabled
                )
                ready.bootstrapped = try seedVault(from: result)
            },
            onDismiss: {
                if let bootstrapped = ready.bootstrapped {
                    onReady(bootstrapped)
                }
            }
        )
    }

    /// Create the encrypted vault database from a completed onboarding result and
    /// seed it with the vault record and the optional first medication.
    @MainActor
    private static func seedVault(from result: OnboardingResult) throws -> Bootstrapped {
        let manager = try VaultDatabaseManager(keyDeriver: FFIDatabaseKeyDeriver())
        let isFirstRun = !manager.databaseExists(vaultId: result.config.vaultID)
        let database = try manager.open(vaultId: result.config.vaultID, vaultKey: result.vaultKey)

        if isFirstRun {
            try database.insertVault(
                Vault(id: result.config.vaultID, name: result.config.vaultName, profileType: .personal)
            )
        }

        if let draft = result.firstMedication, draft.isSaveable {
            let trimmedSchedule = draft.schedule.trimmingCharacters(in: .whitespacesAndNewlines)
            try database.insertMedication(
                Medication(
                    vaultId: result.config.vaultID,
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    dosage: draft.dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: .overTheCounter,
                    frequency: trimmedSchedule.isEmpty ? "As needed" : trimmedSchedule
                )
            )
        }

        return try wire(database: database)
    }

    // MARK: Shared wiring

    /// Build the medication store + drug index over an open vault database.
    @MainActor
    private static func wire(database: AppDatabase) throws -> Bootstrapped {
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
