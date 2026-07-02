import Foundation
import PildoraDataLayer

// MARK: - MedicationRepository

/// Persistence seam for the medication list.
///
/// The feature UI talks to this protocol rather than to any concrete store, so
/// the same views drive either the encrypted, vault-scoped database
/// (`DatabaseMedicationRepository`) or an in-memory fake
/// (`InMemoryMedicationRepository`) used by previews and unit tests.
///
/// All health data handled here is vault-scoped and, when backed by the
/// database, encrypted at rest via the vault key (SQLCipher). Deleting a
/// medication cascades to its schedules, dose logs, and inventory.
public protocol MedicationRepository {
    /// The vault (encryption boundary) this repository reads and writes.
    var vaultID: String { get }
    /// All medications in the active vault, ordered by name.
    func fetchMedications() throws -> [Medication]
    /// All inventory records in the active vault.
    func fetchInventory() throws -> [InventoryRecord]
    /// Insert a new medication.
    func add(_ medication: Medication) throws
    /// Persist edits to an existing medication; returns the stored record
    /// (with its refreshed `updatedAt`).
    @discardableResult
    func update(_ medication: Medication) throws -> Medication
    /// Delete a medication and cascade to its schedules, dose logs, and inventory.
    func delete(medicationId: String) throws
    /// Insert or update a medication's inventory record.
    func upsertInventory(_ record: InventoryRecord) throws
}

// MARK: - Database-backed repository

/// `MedicationRepository` backed by the encrypted `AppDatabase` for one vault.
///
/// This is the production source of truth. When the app links SQLCipher
/// (`GRDBCIPHER`), every write here is encrypted at rest with the vault key;
/// `AppDatabase`'s foreign keys make `delete` cascade to child rows.
public struct DatabaseMedicationRepository: MedicationRepository {
    private let database: AppDatabase
    public let vaultID: String

    public init(database: AppDatabase, vaultId: String) {
        self.database = database
        self.vaultID = vaultId
    }

    public func fetchMedications() throws -> [Medication] {
        try database.fetchMedications(vaultId: vaultID)
    }

    public func fetchInventory() throws -> [InventoryRecord] {
        try database.fetchInventory(vaultId: vaultID)
    }

    public func add(_ medication: Medication) throws {
        try database.insertMedication(medication)
    }

    @discardableResult
    public func update(_ medication: Medication) throws -> Medication {
        try database.updateMedication(medication)
    }

    public func delete(medicationId: String) throws {
        try database.deleteMedication(id: medicationId)
    }

    public func upsertInventory(_ record: InventoryRecord) throws {
        try database.upsertInventory(record)
    }
}

// MARK: - In-memory repository

/// Non-persistent `MedicationRepository` for previews, unit tests, and the
/// macOS toolchain build. Mirrors the database's cascade behavior in memory.
///
/// Not thread-safe: intended to be driven from a single actor (the `@MainActor`
/// store). `@unchecked Sendable` reflects that single-threaded contract.
public final class InMemoryMedicationRepository: MedicationRepository, @unchecked Sendable {
    public let vaultID: String
    private var medications: [Medication]
    private var inventory: [String: InventoryRecord]

    public init(
        vaultID: String = SampleData.vaultId,
        medications: [Medication] = [],
        inventory: [InventoryRecord] = []
    ) {
        self.vaultID = vaultID
        self.medications = medications
        self.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.medicationId, $0) })
    }

    public func fetchMedications() throws -> [Medication] {
        medications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func fetchInventory() throws -> [InventoryRecord] {
        Array(inventory.values)
    }

    public func add(_ medication: Medication) throws {
        medications.removeAll { $0.id == medication.id }
        medications.append(medication)
    }

    @discardableResult
    public func update(_ medication: Medication) throws -> Medication {
        var stored = medication
        stored.updatedAt = Date()
        if let idx = medications.firstIndex(where: { $0.id == stored.id }) {
            medications[idx] = stored
        } else {
            medications.append(stored)
        }
        return stored
    }

    public func delete(medicationId: String) throws {
        medications.removeAll { $0.id == medicationId }
        inventory[medicationId] = nil // cascade
    }

    public func upsertInventory(_ record: InventoryRecord) throws {
        inventory[record.medicationId] = record
    }
}
