import XCTest

final class WL5024ControlUITests: XCTestCase {
    @MainActor
    func testDemoNavigationAndAccessibleControlNames() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Dell WL5024"].waitForExistence(timeout: 5))

        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.exists)
        XCTAssertTrue(refresh.isEnabled)

        let wearAndAutomation = app.staticTexts["Wear & Automation"]
        XCTAssertTrue(wearAndAutomation.exists)
        wearAndAutomation.click()

        let automaticMedia = app.switches["Automatically pause and resume media"]
        XCTAssertTrue(automaticMedia.waitForExistence(timeout: 2))
        XCTAssertTrue(automaticMedia.isEnabled)

        app.staticTexts["Diagnostics"].click()
        XCTAssertTrue(app.buttons["Collect & Export Log…"].waitForExistence(timeout: 2))
    }
}
