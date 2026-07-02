import Foundation
import PildoraDataLayer
import PildoraMedicationList

/// Wires the app's runtime dependencies into a persistence-backed
/// `MedicationStore`: the encrypted vault database, the vault key, and the local
/// drug autocomplete index.
enum AppBootstrap {

    /// The single default vault this slice operates on. Multi-vault selection is
    /// a later milestone; every row is still vault-scoped from day one.
    static let defaultVaultID = "default"

    /// Build the fully wired store. Runs on the main actor because
    /// `MedicationStore` is `@MainActor`-isolated.
    @MainActor
    static func makeStore() throws -> MedicationStore {
        // UI tests run against a clean, in-memory vault so each launch starts
        // from a known empty state, while still exercising the real on-device
        // drug autocomplete index.
        if ProcessInfo.processInfo.arguments.contains("-uitesting") {
            let index = try DrugSeed.openOrBuildIndex()
            let repository = InMemoryMedicationRepository(vaultID: defaultVaultID)
            return try MedicationStore(repository: repository, drugSuggester: index)
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
        let index = try DrugSeed.openOrBuildIndex()

        return try MedicationStore(repository: repository, drugSuggester: index)
    }
}
