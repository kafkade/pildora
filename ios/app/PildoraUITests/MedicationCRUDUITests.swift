import XCTest

/// End-to-end UI tests for medication CRUD with drug-name autocomplete.
///
/// The app is launched with `-uitesting`, which starts it against a clean,
/// in-memory vault (see `AppBootstrap`) while still using the real on-device
/// drug index, so autocomplete behaves exactly as in production.
final class MedicationCRUDUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }

    /// Add a medication by picking a drug-index autocomplete suggestion.
    func testAddMedicationViaAutocomplete() {
        let app = launchApp()

        app.buttons["add-medication-button"].tap()

        let nameField = app.textFields["medication-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Lisin")

        // The FTS5 index should surface "Lisinopril" as a suggestion.
        let suggestion = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Lisinopril")
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()

        let dosageField = app.textFields["medication-dosage-field"]
        dosageField.tap()
        dosageField.typeText("10 mg")

        app.buttons["save-medication-button"].tap()

        XCTAssertTrue(app.staticTexts["Lisinopril"].waitForExistence(timeout: 5))
    }

    /// Add a supplement by free text (not necessarily in the drug index).
    func testAddSupplementFreeText() {
        let app = launchApp()

        app.buttons["add-medication-button"].tap()

        let nameField = app.textFields["medication-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Ashwagandha Root")

        let dosageField = app.textFields["medication-dosage-field"]
        dosageField.tap()
        dosageField.typeText("600 mg")

        app.buttons["save-medication-button"].tap()

        XCTAssertTrue(app.staticTexts["Ashwagandha Root"].waitForExistence(timeout: 5))
    }

    /// Edit an existing medication and see the change reflected immediately.
    func testEditMedication() {
        let app = launchApp()
        addSimpleMedication(app, name: "Metformin", dosage: "500 mg")

        app.staticTexts["Metformin"].tap()
        app.buttons["edit-medication-button"].tap()

        let dosageField = app.textFields["medication-dosage-field"]
        XCTAssertTrue(dosageField.waitForExistence(timeout: 5))
        clear(dosageField)
        dosageField.typeText("1000 mg")

        app.buttons["save-medication-button"].tap()

        XCTAssertTrue(app.staticTexts["Metformin 1000 mg"].waitForExistence(timeout: 5))
    }

    /// Delete a medication through the confirmation dialog.
    func testDeleteMedication() {
        let app = launchApp()
        addSimpleMedication(app, name: "Ibuprofen", dosage: "200 mg")

        app.staticTexts["Ibuprofen"].tap()
        app.buttons["delete-medication-button"].tap()

        // Confirm in the destructive dialog.
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No Medications"].waitForExistence(timeout: 5)
            || !app.staticTexts["Ibuprofen"].waitForExistence(timeout: 2))
    }

    // MARK: Helpers

    private func addSimpleMedication(_ app: XCUIApplication, name: String, dosage: String) {
        app.buttons["add-medication-button"].tap()
        let nameField = app.textFields["medication-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        let dosageField = app.textFields["medication-dosage-field"]
        dosageField.tap()
        dosageField.typeText(dosage)
        app.buttons["save-medication-button"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    private func clear(_ element: XCUIElement) {
        element.tap()
        guard let value = element.value as? String, !value.isEmpty else { return }
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
        element.typeText(deletes)
    }
}
