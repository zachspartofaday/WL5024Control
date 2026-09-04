import XCTest

final class WL5024ControlUITests: XCTestCase {
    private let destinations = [
        "Overview",
        "Noise Control",
        "Calls & Microphone",
        "Wear & Automation",
        "Device",
        "Diagnostics",
    ]

    @MainActor
    func testReadyRegularLayoutAllDestinationsAndAccessibleControls() throws {
        let app = launch(["--demo"])
        XCTAssertTrue(app.staticTexts["Dell WL5024"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh"].isEnabled)

        for destination in destinations {
            navigate(to: destination, in: app)
            attachScreenshot(named: "Regular-\(destination)", app: app)
        }

        navigate(to: "Wear & Automation", in: app)
        let label = app.staticTexts["setting.label.wearDetection"]
        let checkBox = app.checkBoxes["Wear detection"]
        XCTAssertTrue(checkBox.waitForExistence(timeout: 2))
        XCTAssertTrue(checkBox.isEnabled)
        XCTAssertLessThan(label.frame.maxX, checkBox.frame.minX)

        let automaticMedia = app.checkBoxes["Automatically pause and resume media"]
        XCTAssertEqual(checkBox.frame.maxX, automaticMedia.frame.maxX, accuracy: 2)
        let powerOff = app.popUpButtons["Automatic power off"]
        XCTAssertTrue(powerOff.waitForExistence(timeout: 2))
        XCTAssertEqual(checkBox.frame.maxX, powerOff.frame.maxX, accuracy: 2)

        navigate(to: "Calls & Microphone", in: app)
        let sidetone = app.popUpButtons["Sidetone"]
        let busyLight = app.checkBoxes["Busy light"]
        XCTAssertTrue(sidetone.waitForExistence(timeout: 2))
        XCTAssertTrue(busyLight.exists)
        XCTAssertEqual(sidetone.frame.maxX, busyLight.frame.maxX, accuracy: 2)
    }

    @MainActor
    func testMinimumLayoutStacksWithoutOverlapAcrossAllDestinations() throws {
        let app = launch(["--demo", "--ui-minimum"])
        XCTAssertTrue(app.staticTexts["Dell WL5024"].waitForExistence(timeout: 5))

        for destination in destinations {
            navigate(to: destination, in: app)
            attachScreenshot(named: "Minimum-\(destination)", app: app)
        }

        navigate(to: "Wear & Automation", in: app)
        let label = app.staticTexts["setting.label.autoPowerOff"]
        let selector = app.popUpButtons["Automatic power off"]
        XCTAssertTrue(selector.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(label.frame.maxY, selector.frame.minY)
        XCTAssertFalse(label.frame.intersects(selector.frame))
    }

    @MainActor
    func testReadOnlyStateExplainsDisabledControlAndMenuItem() throws {
        let app = launch(["--read-only"])
        navigate(to: "Wear & Automation", in: app)

        let automaticMedia = app.checkBoxes["Automatically pause and resume media"]
        XCTAssertTrue(automaticMedia.waitForExistence(timeout: 3))
        XCTAssertFalse(automaticMedia.isEnabled)
        XCTAssertTrue(app.staticTexts["Current value available; writing awaits hardware validation"].exists)

        let statusItem = app.statusItems["WL5024 connected"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 3))
        statusItem.click()
        XCTAssertTrue(app.menuItems["Automatic media control: On"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Read-only — validation pending"].exists)
        XCTAssertTrue(app.menuItems["Open Settings…"].exists)
    }

    @MainActor
    func testExperimentalSettingsOfferExplicitWritesWithoutClaimingCurrentValues() throws {
        let app = launch(["--experimental"])

        navigate(to: "Wear & Automation", in: app)
        let automaticMedia = app.descendants(matching: .any)["setting.experimental.automaticMedia"]
        XCTAssertTrue(automaticMedia.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "Experimental write — response and read-back verification required"
        ].exists)
        automaticMedia.click()
        let turnOn = automaticMedia.menuItems["Turn On"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 2))
        turnOn.click()
        XCTAssertTrue(app.checkBoxes["Automatically pause and resume media"].waitForExistence(timeout: 2))

        navigate(to: "Noise Control", in: app)
        XCTAssertTrue(app.staticTexts["setting.label.environmentDetection"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)[
            "setting.experimental.advancedPassthrough"
        ].exists)

        navigate(to: "Calls & Microphone", in: app)
        XCTAssertTrue(app.descendants(matching: .any)[
            "setting.experimental.sidetone"
        ].waitForExistence(timeout: 2))

        navigate(to: "Device", in: app)
        XCTAssertTrue(app.descendants(matching: .any)[
            "setting.experimental.voiceGuidance"
        ].waitForExistence(timeout: 2))
    }

    @MainActor
    func testDiagnosticsSelectableValuesProgressCancellationAndFocusReturn() throws {
        let app = launch(["--demo", "--ui-observe-export-progress", "--ui-focus-probe"])
        navigate(to: "Diagnostics", in: app)
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "diagnostics.protocol.value").count, 0)

        let discoveryButton = app.buttons["Run Read-only Discovery"]
        XCTAssertTrue(discoveryButton.waitForExistence(timeout: 2))
        XCTAssertTrue(discoveryButton.isEnabled)
        discoveryButton.click()
        XCTAssertTrue(app.staticTexts["diagnostics.discovery.summary"].waitForExistence(timeout: 3))

        let exportButton = app.buttons["Collect & Export Log…"]
        exportButton.click()
        XCTAssertTrue(app.staticTexts["diagnostics.export.phase"].waitForExistence(timeout: 1))
        let cancel = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()

        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(exportButton.isEnabled)
        XCTAssertTrue(app.staticTexts["Export button focused"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDiagnosticResultAlertDismissalRestoresFocus() throws {
        let app = launch(["--demo", "--ui-export-direct", "--ui-focus-probe"])
        navigate(to: "Diagnostics", in: app)
        let exportButton = app.buttons["Collect & Export Log…"]
        exportButton.click()

        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Diagnostic Export"].exists)
        alert.buttons["Done"].click()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Export button focused"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAppearanceAndAccessibilityLaunchProfiles() throws {
        let profiles = [
            ["--demo", "--appearance-light"],
            ["--demo", "--appearance-dark"],
            ["--demo", "-AppleIncreaseContrast", "YES"],
            ["--demo", "-AppleReduceTransparency", "YES"],
        ]

        for arguments in profiles {
            let app = launch(arguments)
            XCTAssertTrue(app.staticTexts["Dell WL5024"].waitForExistence(timeout: 5))
            navigate(to: "Calls & Microphone", in: app)
            XCTAssertTrue(app.popUpButtons["Sidetone"].exists)
            app.terminate()
        }
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3",
        ]
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 1) {
            let connectedStatusItem = app.statusItems["WL5024 connected"]
            let disconnectedStatusItem = app.statusItems["WL5024 disconnected"]
            let statusItem = connectedStatusItem.waitForExistence(timeout: 5)
                ? connectedStatusItem
                : disconnectedStatusItem
            XCTAssertTrue(statusItem.exists)
            statusItem.click()
            let openSettings = app.menuItems["Open Settings…"]
            XCTAssertTrue(openSettings.waitForExistence(timeout: 2))
            openSettings.click()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
        addTeardownBlock { @MainActor in
            if app.state != .notRunning { app.terminate() }
        }
        return app
    }

    @MainActor
    private func navigate(to destination: String, in app: XCUIApplication) {
        let destinationElement = app.outlines["Settings destinations"].staticTexts[destination]
        XCTAssertTrue(destinationElement.waitForExistence(timeout: 3), "Missing \(destination)")
        destinationElement.click()
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
