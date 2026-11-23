import XCTest

/// Walks the main screens and attaches a screenshot of each. The screenshots workflow
/// exports the attachments as PNGs for the README; the walk also doubles as a smoke test.
@MainActor
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        await MainActor.run {
            app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func type(_ id: String, _ text: String) {
        app.textFields[id].tap()
        app.textFields[id].typeText(text)
    }

    func testWalkthrough() {
        snap("01-empty")

        app.buttons["create-group-empty"].tap()
        type("group-name", "Umoja Chama")
        type("my-name", "Wanjiru")
        type("my-phone", "0712345678")
        snap("02-create-group")
        app.buttons["create-group-confirm"].tap()

        let row = app.staticTexts["Umoja Chama"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["pot-amount"].waitForExistence(timeout: 5))

        app.buttons["members-link"].tap()
        for (name, phone) in [("Amina", "0733000222"), ("Brian", "0744000333")] {
            app.buttons["add-member"].tap()
            type("member-name", name)
            type("member-phone", phone)
            app.buttons["add-member-confirm"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        }
        snap("03-members")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        for name in ["Wanjiru", "Amina"] {
            app.buttons["record-cash-link"].tap()
            app.buttons["cash-member"].tap()
            app.buttons[name].tap()
            app.buttons["cash-save"].tap()
            XCTAssertTrue(app.staticTexts["pot-amount"].waitForExistence(timeout: 5))
        }
        snap("04-dashboard")

        app.buttons["contribute-link"].tap()
        XCTAssertTrue(app.buttons["pay-button"].waitForExistence(timeout: 5))
        snap("05-contribute")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.scrolledTo(app.buttons["loans-link"]).tap()
        app.buttons["request-loan"].tap()
        type("amount-field", "5000")
        snap("06-request-loan")
        app.buttons["request-loan-confirm"].tap()
        let borrower = app.staticTexts["Wanjiru"].firstMatch
        XCTAssertTrue(borrower.waitForExistence(timeout: 5))
        snap("07-loans")
        borrower.tap()
        XCTAssertTrue(app.staticTexts["Loan"].firstMatch.waitForExistence(timeout: 5))
        snap("08-loan-detail")
    }

    /// The SMS import: two payments, money the treasurer sent out, and a code pasted twice.
    func testImportWalkthrough() {
        app.buttons["create-group-empty"].tap()
        type("group-name", "Umoja Chama")
        type("my-name", "Wanjiru")
        type("my-phone", "0712345678")
        app.buttons["create-group-confirm"].tap()
        app.staticTexts["Umoja Chama"].firstMatch.tap()

        app.buttons["members-link"].tap()
        for (name, phone) in [("Amina Wanjiku", "0733000222"), ("Brian Otieno", "0744000333")] {
            app.buttons["add-member"].tap()
            type("member-name", name)
            type("member-phone", phone)
            app.buttons["add-member-confirm"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.scrolledTo(app.buttons["import-link"]).tap()
        let paste = app.textViews["import-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let amina = "TKL3QZ8M2A Confirmed.You have received Ksh2,000.00 from AMINA WANJIKU 0733000222 on 3/11/26 at 7:42 PM New M-PESA balance is Ksh12,340.00."
        paste.typeText([
            amina,
            "TKM8RT2P4B Confirmed.You have received Ksh1,500.00 from BRIAN OTIENO 0744***333 on 4/11/26 at 9:30 PM New M-PESA balance is Ksh13,840.00.",
            "TKN5WX7C3D Confirmed. Ksh500.00 sent to BRIAN OTIENO 0744000333 on 5/11/26 at 6:10 PM. New M-PESA balance is Ksh13,340.00.",
            amina,
        ].joined(separator: "\n\n"))
        snap("09-import-paste")
        app.buttons["import-read"].tap()
        XCTAssertTrue(app.scrolledTo(app.staticTexts["Ready"].firstMatch).waitForExistence(timeout: 10))
        snap("10-import-results")
        app.swipeUp()
        snap("11-import-results-more")
    }
}
