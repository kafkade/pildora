import XCTest
@testable import PildoraMedicationList

final class SearchFilterTests: XCTestCase {
    private let meds = SampleData.medications

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(MedicationStore.filter(meds, query: "").count, meds.count)
        XCTAssertEqual(MedicationStore.filter(meds, query: "   ").count, meds.count)
    }

    func testMatchesByNameCaseInsensitively() {
        let results = MedicationStore.filter(meds, query: "metf")
        XCTAssertEqual(results.map(\.name), ["Metformin"])
    }

    func testMatchesByGenericName() {
        // "metformin hydrochloride" is the generic name on Metformin.
        let results = MedicationStore.filter(meds, query: "hydrochloride")
        XCTAssertEqual(results.map(\.name), ["Metformin"])
    }

    func testNoMatchesReturnsEmpty() {
        XCTAssertTrue(MedicationStore.filter(meds, query: "zzzznotamed").isEmpty)
    }

    func testGroupingOrdersByCategoryThenName() {
        let sections = MedicationStore.group(meds)
        // Prescription should sort before supplement/vitamin/OTC by sortOrder.
        XCTAssertEqual(sections.first?.category, .prescription)
        // Categories are unique across sections.
        XCTAssertEqual(Set(sections.map(\.category)).count, sections.count)
        // Medications within a section are alphabetized.
        for section in sections {
            let names = section.medications.map(\.name)
            XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        }
    }
}
