import XCTest
@testable import PildoraDataLayer

/// Verifies the one-vault-one-file layout: separate files per vault, data
/// persists across reopen, and deletion removes the file and its sidecars.
final class VaultDatabaseManagerTests: XCTestCase {
    private var directory: URL!
    private var manager: VaultDatabaseManager!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pildora-vaults-\(UUID().uuidString)", isDirectory: true)
        manager = try VaultDatabaseManager(
            directory: directory,
            keyDeriver: HKDFTestKeyDeriver(),
            fileProtection: false
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEachVaultGetsItsOwnFile() {
        XCTAssertNotEqual(
            manager.databaseURL(vaultId: "a").path,
            manager.databaseURL(vaultId: "b").path
        )
        XCTAssertTrue(manager.databaseURL(vaultId: "a").lastPathComponent.contains("vault-a"))
    }

    func testOpenCreatesFileAndPersistsAcrossReopen() throws {
        XCTAssertFalse(manager.databaseExists(vaultId: "v1"))

        let key = TestFixtures.vaultKey()
        let db = try manager.open(vaultId: "v1", vaultKey: key)
        try db.insertVault(Vault(id: "v1", name: "Personal"))
        try db.insertMedication(Medication(id: "m1", vaultId: "v1", name: "Med", dosage: "1"))

        XCTAssertTrue(manager.databaseExists(vaultId: "v1"))

        let reopened = try manager.open(vaultId: "v1", vaultKey: key)
        XCTAssertEqual(try reopened.fetchMedication(id: "m1")?.name, "Med")
    }

    func testDeleteRemovesFileAndSidecars() throws {
        let db = try manager.open(vaultId: "v1", vaultKey: TestFixtures.vaultKey())
        try db.insertVault(Vault(id: "v1", name: "Personal"))
        // Force a WAL sidecar to exist by writing.
        try db.insertMedication(Medication(id: "m1", vaultId: "v1", name: "Med", dosage: "1"))
        XCTAssertTrue(manager.databaseExists(vaultId: "v1"))

        XCTAssertTrue(try manager.deleteDatabase(vaultId: "v1"))
        XCTAssertFalse(manager.databaseExists(vaultId: "v1"))
        for suffix in ["-wal", "-shm"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: manager.databaseURL(vaultId: "v1").path + suffix)
            )
        }
    }

    func testDeletingMissingVaultReturnsFalse() throws {
        XCTAssertFalse(try manager.deleteDatabase(vaultId: "never-created"))
    }
}
