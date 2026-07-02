import Foundation
import PildoraDrugIndex
import XCTest
@testable import PildoraMedicationList

/// A deterministic autocomplete provider so editor/store suggestion behavior can
/// be tested without a real FTS5 index.
private struct FakeSuggester: DrugSuggesting {
    let results: [DrugSuggestion]
    func suggestions(matching query: String, limit: Int) throws -> [DrugSuggestion] {
        results
            .filter { $0.displayName.lowercased().hasPrefix(query.lowercased()) }
            .prefix(limit)
            .map { $0 }
    }
}

@MainActor
final class EditorSuggestionsTests: XCTestCase {

    private func makeStore(suggester: DrugSuggesting?) -> MedicationStore {
        MedicationStore(
            medications: [],
            inventory: [],
            references: [],
            repository: InMemoryMedicationRepository(vaultID: "vault-x"),
            drugSuggester: suggester
        )
    }

    func testDraftMedicationCarriesActiveVault() {
        let store = makeStore(suggester: nil)
        XCTAssertEqual(store.activeVaultID, "vault-x")
        XCTAssertEqual(store.makeDraftMedication().vaultId, "vault-x")
        XCTAssertFalse(store.supportsDrugSuggestions)
    }

    func testSuggestionsReturnEmptyForShortQuery() async {
        let store = makeStore(suggester: FakeSuggester(results: [
            DrugSuggestion(id: "drug-1", displayName: "Ibuprofen", genericName: "ibuprofen", kind: .drug),
        ]))
        let one = await store.drugSuggestions(matching: "i")
        XCTAssertTrue(one.isEmpty)
    }

    func testSuggestionsMatchPrefix() async {
        let store = makeStore(suggester: FakeSuggester(results: [
            DrugSuggestion(id: "drug-1", displayName: "Ibuprofen", genericName: "ibuprofen", kind: .drug),
            DrugSuggestion(id: "supp-1", displayName: "Iron", kind: .supplement),
            DrugSuggestion(id: "drug-2", displayName: "Metformin", genericName: "metformin", kind: .drug),
        ]))
        let results = await store.drugSuggestions(matching: "ir")
        XCTAssertEqual(results.map(\.id), ["supp-1"])
        XCTAssertEqual(results.first?.subtitle, "Supplement")
    }

    func testSuggestionsEmptyWhenNoIndexConfigured() async {
        let store = makeStore(suggester: nil)
        XCTAssertTrue(store.supportsDrugSuggestions == false)
        let results = await store.drugSuggestions(matching: "ibup")
        XCTAssertTrue(results.isEmpty)
    }
}
