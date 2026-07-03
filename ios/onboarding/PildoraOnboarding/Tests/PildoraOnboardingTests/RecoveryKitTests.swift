import XCTest
@testable import PildoraOnboarding

final class RecoveryKitTests: XCTestCase {

    // MARK: Formatting

    func testDisplayStringGroupsFiveWithChecksum() {
        let key = [UInt8](repeating: 0, count: 32)
        let s = RecoveryKeyFormatting.displayString(for: key) { _ in [0, 0] }
        let groups = s.split(separator: "-")
        XCTAssertGreaterThan(groups.count, 1)
        // Every group is at most 5 characters and non-empty.
        for group in groups {
            XCTAssertLessThanOrEqual(group.count, 5)
            XCTAssertGreaterThan(group.count, 0)
        }
        // 32 bytes -> 52 base32 chars + 2 checksum chars = 54 chars total.
        let charCount = s.replacingOccurrences(of: "-", with: "").count
        XCTAssertEqual(charCount, 54)
    }

    func testDisplayStringUsesCrockfordAlphabetOnly() {
        let key = (0..<32).map { UInt8($0) }
        let s = RecoveryKeyFormatting.displayString(for: key) { _ in [1, 2] }
        let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ-")
        XCTAssertTrue(s.allSatisfy { allowed.contains($0) }, "unexpected char in \(s)")
        // No ambiguous characters.
        XCTAssertFalse(s.contains("I"))
        XCTAssertFalse(s.contains("L"))
        XCTAssertFalse(s.contains("O"))
        XCTAssertFalse(s.contains("U"))
    }

    func testDisplayStringIsDeterministic() {
        let key = (0..<32).map { UInt8($0 &* 7) }
        let a = RecoveryKeyFormatting.displayString(for: key) { _ in [3, 4] }
        let b = RecoveryKeyFormatting.displayString(for: key) { _ in [3, 4] }
        XCTAssertEqual(a, b)
    }

    func testDifferentKeysProduceDifferentStrings() {
        let a = RecoveryKeyFormatting.displayString(for: [UInt8](repeating: 1, count: 32)) { _ in [0, 0] }
        let b = RecoveryKeyFormatting.displayString(for: [UInt8](repeating: 2, count: 32)) { _ in [0, 0] }
        XCTAssertNotEqual(a, b)
    }

    // MARK: Document

    func testDocumentPlainTextContainsKeyAndWarning() {
        let doc = RecoveryDocument.standard(vaultName: "Me", recoveryKey: "AAAAA-BBBBB-CCCCC")
        let text = doc.plainText
        XCTAssertTrue(text.contains("AAAAA-BBBBB-CCCCC"))
        XCTAssertTrue(text.lowercased().contains("permanently unrecoverable"))
        XCTAssertTrue(text.contains("Me"))
        XCTAssertTrue(text.contains("Pildora"))
    }

    func testStandardDocumentHasInstructionsAndWarning() {
        let doc = RecoveryDocument.standard(vaultName: "Me", recoveryKey: "KEY")
        XCTAssertFalse(doc.instructions.isEmpty)
        XCTAssertFalse(doc.warning.isEmpty)
    }

    // MARK: PDF

    func testPDFRenderProducesNonEmptyData() {
        let doc = RecoveryDocument.standard(vaultName: "Me", recoveryKey: "AAAAA-BBBBB")
        let data = RecoveryKitPDFRenderer.render(doc)
        XCTAssertFalse(data.isEmpty)
    }
}
