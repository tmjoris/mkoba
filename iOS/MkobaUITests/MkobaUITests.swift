import XCTest

/// End-to-end through the real UI with an in-memory store. No server is needed: every
/// action here is an offline write, which is the whole point of the app.
@MainActor
final class MkobaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        await MainActor.run {
            app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }

    func testCreateGroupAddMemberRecordCash() {
        app.buttons["create-group-empty"].tap()
        app.textFields["group-name"].tap()
        app.textFields["group-name"].typeText("Umoja Chama")
        app.textFields["my-name"].tap()
        app.textFields["my-name"].typeText("Wanjiru")
        app.textFields["my-phone"].tap()
        app.textFields["my-phone"].typeText("0712345678")
        app.buttons["create-group-confirm"].tap()

        let row = app.staticTexts["Umoja Chama"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["pot-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["pot-amount"].label, "KES 0")

        app.buttons["members-link"].tap()
        app.buttons["add-member"].tap()
        app.textFields["member-name"].tap()
        app.textFields["member-name"].typeText("Amina")
        app.textFields["member-phone"].tap()
        app.textFields["member-phone"].typeText("0733000222")
        app.buttons["add-member-confirm"].tap()
        XCTAssertTrue(app.staticTexts["Amina"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["record-cash-link"].tap()
        app.buttons["cash-member"].tap()
        app.buttons["Amina"].tap()
        app.buttons["cash-save"].tap()
        XCTAssertTrue(app.staticTexts["pot-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["pot-amount"].label, "KES 2,000")
    }

    func testLoanAbovePolicyIsRefusedWithReason() {
        app.buttons["create-group-empty"].tap()
        app.textFields["group-name"].tap()
        app.textFields["group-name"].typeText("Test")
        app.textFields["my-name"].tap()
        app.textFields["my-name"].typeText("Me")
        app.textFields["my-phone"].tap()
        app.textFields["my-phone"].typeText("0712345678")
        app.buttons["create-group-confirm"].tap()
        app.staticTexts["Test"].firstMatch.tap()

        app.buttons["loans-link"].tap()
        app.buttons["request-loan"].tap()
        app.textFields["amount-field"].tap()
        app.textFields["amount-field"].typeText("5000")
        app.buttons["request-loan-confirm"].tap()
        XCTAssertTrue(app.staticTexts["error-banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["error-banner"].label.contains("capped"))
    }
}
