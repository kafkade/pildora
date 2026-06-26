import XCTest
@testable import PildoraMedicationList

@MainActor
final class JSONExportTests: XCTestCase {

    private func makeStore() -> MedicationStore { .sample() }

    func testDocumentIncludesAllMedicationsSortedByName() {
        let store = makeStore()
        let doc = DataExporter.document(from: store)
        XCTAssertEqual(doc.medications.count, store.medications.count)
        let names = doc.medications.map(\.medication.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testMetaCarriesDisclaimerAndSchemaVersion() {
        let store = makeStore()
        let doc = DataExporter.document(from: store)
        XCTAssertEqual(doc.meta.schemaVersion, DataExporter.schemaVersion)
        XCTAssertEqual(doc.meta.disclaimer, DrugReference.disclaimer)
        XCTAssertEqual(doc.meta.app, "Pildora")
    }

    func testEntryBundlesInventoryAndReference() {
        let store = makeStore()
        let doc = DataExporter.document(from: store)
        let metformin = doc.medications.first { $0.medication.id == "med-2" }
        XCTAssertNotNil(metformin?.inventory)
        XCTAssertEqual(metformin?.reference?.source, "openFDA")
    }

    func testJSONRoundTrips() throws {
        let store = makeStore()
        let doc = DataExporter.document(from: store)
        let data = try DataExporter.jsonData(for: doc)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportDocument.self, from: data)
        XCTAssertEqual(decoded.medications.count, doc.medications.count)
        XCTAssertEqual(decoded.meta.disclaimer, doc.meta.disclaimer)
    }

    func testSuggestedFilename() {
        let name = DataExporter.suggestedFilename(ext: "json")
        XCTAssertTrue(name.hasPrefix("pildora-export-"))
        XCTAssertTrue(name.hasSuffix(".json"))
    }

    func testDoctorReportContainsDisclaimerAndMedications() {
        let store = makeStore()
        let report = DoctorReport.build(from: store)
        let text = report.plainText
        XCTAssertTrue(text.contains(DrugReference.disclaimer))
        XCTAssertTrue(text.contains("Metformin"))
        // Rendered bytes are always produced (PDF on iOS, text fallback elsewhere).
        XCTAssertFalse(PDFReportRenderer.render(report).isEmpty)
    }
}
