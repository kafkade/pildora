import Foundation
import Combine

// MARK: - Grouped Section

/// A category-grouped section of medications for the list view.
public struct MedicationSection: Identifiable {
    public let category: MedicationCategory
    public let medications: [Medication]
    public var id: MedicationCategory { category }
}

// MARK: - Medication Store

/// In-memory, observable source of truth for the feature.
///
/// Holds medications, their inventory records, drug reference data and app
/// settings, and derives the search-filtered, category-grouped list the UI
/// renders. Designed to be replaced by a GRDB/SQLCipher-backed store (#44/#48)
/// without changing the views: the published surface is what the views depend
/// on.
@MainActor
public final class MedicationStore: ObservableObject {

    // MARK: Published state

    @Published public private(set) var medications: [Medication]
    @Published public private(set) var inventoryByMedication: [String: InventoryRecord]
    @Published public private(set) var referencesById: [String: DrugReference]
    @Published public var settings: AppSettings
    /// Search text bound to the list's search field. Matches name + generic name.
    @Published public var searchText: String = ""
    /// Surfaces the most recent persistence error to the UI (e.g. a failed
    /// save/delete). Cleared on the next successful mutation.
    @Published public private(set) var lastError: String?

    private let notifier: RefillNotifying
    /// Persistence backend. Mutations write through here before published state
    /// is updated, so the encrypted database (or the in-memory fake) stays the
    /// source of truth.
    private let repository: MedicationRepository
    /// Local drug-name autocomplete provider (bundled FTS5 index in the app,
    /// a fake in tests/previews). `nil` disables suggestions gracefully.
    private let drugSuggester: DrugSuggesting?

    // MARK: Init

    public init(
        medications: [Medication],
        inventory: [InventoryRecord],
        references: [DrugReference],
        settings: AppSettings = .default,
        notifier: RefillNotifying = SimulatedRefillNotifier(),
        repository: MedicationRepository? = nil,
        drugSuggester: DrugSuggesting? = nil
    ) {
        self.medications = medications
        self.inventoryByMedication = Dictionary(
            uniqueKeysWithValues: inventory.map { ($0.medicationId, $0) }
        )
        self.referencesById = Dictionary(
            uniqueKeysWithValues: references.map { ($0.id, $0) }
        )
        self.settings = settings
        self.notifier = notifier
        self.repository = repository
            ?? InMemoryMedicationRepository(medications: medications, inventory: inventory)
        self.drugSuggester = drugSuggester
    }

    /// Load the store from a repository (e.g. the encrypted database).
    /// Reference data is public/plaintext and supplied separately.
    public convenience init(
        repository: MedicationRepository,
        references: [DrugReference] = [],
        settings: AppSettings = .default,
        notifier: RefillNotifying = SimulatedRefillNotifier(),
        drugSuggester: DrugSuggesting? = nil
    ) throws {
        self.init(
            medications: try repository.fetchMedications(),
            inventory: try repository.fetchInventory(),
            references: references,
            settings: settings,
            notifier: notifier,
            repository: repository,
            drugSuggester: drugSuggester
        )
    }

    /// Convenience initializer seeded with bundled sample data.
    public static func sample(notifier: RefillNotifying = SimulatedRefillNotifier()) -> MedicationStore {
        MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            notifier: notifier
        )
    }

    // MARK: Lookups

    public func inventory(for medicationID: String) -> InventoryRecord? {
        inventoryByMedication[medicationID]
    }

    public func reference(for medication: Medication) -> DrugReference? {
        guard let refID = medication.drugReferenceId else { return nil }
        return referencesById[refID]
    }

    // MARK: Medication mutations (CRUD)

    /// Add a new medication (and optional starting inventory), persisting through
    /// the repository before updating published state.
    public func addMedication(_ medication: Medication, inventory: InventoryRecord? = nil) {
        persist {
            try repository.add(medication)
            if let inventory { try repository.upsertInventory(inventory) }
        }
        medications.removeAll { $0.id == medication.id }
        medications.append(medication)
        if let inventory { inventoryByMedication[medication.id] = inventory }
        reevaluateRefill(for: medication.id)
    }

    /// Persist edits to an existing medication and reflect them immediately.
    public func updateMedication(_ medication: Medication) {
        var stored = medication
        persist { stored = try repository.update(medication) }
        if let idx = medications.firstIndex(where: { $0.id == stored.id }) {
            medications[idx] = stored
        } else {
            medications.append(stored)
        }
        reevaluateRefill(for: stored.id)
    }

    /// Delete a medication. The repository cascades to schedules, dose logs, and
    /// inventory; the store drops its inventory row and cancels any reminder.
    public func deleteMedication(id: String) {
        persist { try repository.delete(medicationId: id) }
        medications.removeAll { $0.id == id }
        inventoryByMedication[id] = nil
        notifier.cancelRefillReminder(medicationID: id)
    }

    /// Run a persistence operation, capturing any error into `lastError` so the
    /// UI can surface it. Clears `lastError` on success.
    private func persist(_ work: () throws -> Void) {
        do {
            try work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Editor support

    /// The vault new medications are written to (the repository's active vault).
    public var activeVaultID: String { repository.vaultID }

    /// A blank medication seeded with the active vault, for the "add" editor.
    public func makeDraftMedication() -> Medication {
        Medication(vaultId: activeVaultID, name: "", dosage: "")
    }

    /// Whether drug-name autocomplete is available (an index was injected).
    public var supportsDrugSuggestions: Bool { drugSuggester != nil }

    /// Ranked local autocomplete matches for the medication editor. Runs the
    /// FTS5 query off the main actor and returns `[]` for short/blank queries or
    /// when no index is configured. Never contacts a server.
    public func drugSuggestions(matching query: String, limit: Int = 8) async -> [DrugSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let suggester = drugSuggester else { return [] }
        return await Task.detached(priority: .userInitiated) {
            (try? suggester.suggestions(matching: trimmed, limit: limit)) ?? []
        }.value
    }

    // MARK: Search + grouping

    /// Medications matching the current `searchText` (case/diacritic-insensitive,
    /// over name and generic name). Empty search returns all.
    public var filteredMedications: [Medication] {
        Self.filter(medications, query: searchText)
    }

    /// Static, side-effect-free filter used by the view and unit tests.
    nonisolated public static func filter(_ meds: [Medication], query: String) -> [Medication] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meds }
        return meds.filter { med in
            med.name.localizedCaseInsensitiveContains(trimmed)
                || (med.genericName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// The filtered medications grouped into category sections, each sorted by
    /// name, with sections ordered by `MedicationCategory.sortOrder`.
    public var sections: [MedicationSection] {
        Self.group(filteredMedications)
    }

    /// Static, side-effect-free grouping used by the view and unit tests.
    nonisolated public static func group(_ meds: [Medication]) -> [MedicationSection] {
        let grouped = Dictionary(grouping: meds, by: { $0.category })
        return grouped
            .map { category, meds in
                MedicationSection(
                    category: category,
                    medications: meds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    // MARK: Low stock

    /// Medications currently at or below their refill threshold.
    public var lowStockMedications: [Medication] {
        medications.filter { med in
            inventoryByMedication[med.id]?.isLow ?? false
        }
    }

    // MARK: Inventory mutation

    /// Set the absolute inventory count for a medication, re-evaluating the
    /// refill reminder. Creates an inventory record if none exists.
    public func setInventoryCount(_ count: Int, for medicationID: String) {
        let clamped = max(0, count)
        var record = inventoryByMedication[medicationID]
            ?? InventoryRecord(
                medicationId: medicationID,
                vaultId: vaultId(for: medicationID),
                currentCount: clamped,
                refillThreshold: settings.defaultRefillThreshold
            )
        record.currentCount = clamped
        record.updatedAt = Date()
        inventoryByMedication[medicationID] = record
        persist { try repository.upsertInventory(record) }
        reevaluateRefill(for: medicationID)
    }

    /// Adjust inventory by a delta (e.g. +1 / -1 stepper).
    public func adjustInventory(by delta: Int, for medicationID: String) {
        let current = inventoryByMedication[medicationID]?.currentCount ?? 0
        setInventoryCount(current + delta, for: medicationID)
    }

    /// Update the user-configurable refill threshold for a medication.
    public func setRefillThreshold(_ threshold: Int, for medicationID: String) {
        guard var record = inventoryByMedication[medicationID] else { return }
        record.refillThreshold = max(0, threshold)
        record.updatedAt = Date()
        inventoryByMedication[medicationID] = record
        persist { try repository.upsertInventory(record) }
        reevaluateRefill(for: medicationID)
    }

    /// Toggle whether a refill reminder is scheduled for a medication.
    public func setRefillReminderEnabled(_ enabled: Bool, for medicationID: String) {
        guard var record = inventoryByMedication[medicationID] else { return }
        record.refillReminderEnabled = enabled
        record.updatedAt = Date()
        inventoryByMedication[medicationID] = record
        persist { try repository.upsertInventory(record) }
        reevaluateRefill(for: medicationID)
    }

    /// Record a refill: set the count and stamp the refill date.
    public func recordRefill(newCount: Int, for medicationID: String, date: Date = Date()) {
        var record = inventoryByMedication[medicationID]
            ?? InventoryRecord(
                medicationId: medicationID,
                vaultId: vaultId(for: medicationID),
                currentCount: newCount,
                refillThreshold: settings.defaultRefillThreshold
            )
        record.currentCount = max(0, newCount)
        record.lastRefillDate = date
        record.updatedAt = date
        inventoryByMedication[medicationID] = record
        persist { try repository.upsertInventory(record) }
        reevaluateRefill(for: medicationID)
    }

    /// The owning vault for a medication, used when creating an inventory record.
    /// Falls back to any known medication's vault, then the default vault id.
    private func vaultId(for medicationID: String) -> String {
        medications.first { $0.id == medicationID }?.vaultId
            ?? medications.first?.vaultId
            ?? SampleData.vaultId
    }

    // MARK: Refill notification scheduling

    /// Schedule or cancel the local refill reminder for a medication based on
    /// its current inventory state and the app-wide setting.
    private func reevaluateRefill(for medicationID: String) {
        guard let med = medications.first(where: { $0.id == medicationID }),
              let record = inventoryByMedication[medicationID]
        else { return }

        let shouldNotify = settings.refillRemindersEnabled
            && record.refillReminderEnabled
            && record.isLow

        if shouldNotify {
            notifier.scheduleRefillReminder(
                RefillReminder(
                    medicationID: med.id,
                    medicationName: med.name,
                    remainingCount: record.currentCount,
                    unitNoun: med.form.unitNoun
                )
            )
        } else {
            notifier.cancelRefillReminder(medicationID: medicationID)
        }
    }

    /// Re-evaluate refill reminders for every medication. Call on launch /
    /// foreground to bring the notification queue in sync with current state.
    public func reevaluateAllRefills() {
        for med in medications {
            reevaluateRefill(for: med.id)
        }
    }
}
