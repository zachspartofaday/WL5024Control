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
        let explanation = app.staticTexts["setting.explanation.wearDetection"]
        let checkBox = app.checkBoxes["Wear detection"]
        XCTAssertTrue(checkBox.waitForExistence(timeout: 2))
        XCTAssertTrue(checkBox.isEnabled)
        XCTAssertEqual(checkBox.label, "Wear detection")
        XCTAssertTrue(explanation.exists)
        XCTAssertLessThan(explanation.frame.maxX, checkBox.frame.minX)

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
        let explanation = app.staticTexts["setting.explanation.autoPowerOff"]
        let selector = app.popUpButtons["Automatic power off"]
        XCTAssertTrue(selector.waitForExistence(timeout: 2))
        XCTAssertEqual(selector.label, "Automatic power off")
        XCTAssertTrue(explanation.exists)
        XCTAssertLessThanOrEqual(explanation.frame.maxY, selector.frame.minY)
        XCTAssertFalse(explanation.frame.intersects(selector.frame))
    }

    @MainActor
    func testSettingRowsExposeOneControlIdentityWithoutLayoutProbes() throws {
        let app = launch(["--demo"])
        navigate(to: "Wear & Automation", in: app)

        XCTAssertTrue(app.checkBoxes["Wear detection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Wear detection"].exists)
        XCTAssertTrue(app.staticTexts["setting.explanation.wearDetection"].exists)
    }

    @MainActor
    func testReadOnlyStateExplainsDisabledControlAndMenuItem() throws {
        let app = launch(["--read-only"])
        navigate(to: "Wear & Automation", in: app)

        let automaticMedia = app.checkBoxes["Automatically pause and resume media"]
        XCTAssertTrue(automaticMedia.waitForExistence(timeout: 3))
        XCTAssertFalse(automaticMedia.isEnabled)
        let explanation = app.staticTexts["setting.explanation.automaticMedia"]
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(app.staticTexts[
            "Turn this off to prevent the headset from launching or controlling music when you put it on or remove it."
        ].exists)
        let readiness = app.staticTexts["setting.status.automaticMedia"]
        XCTAssertTrue(readiness.exists)
        XCTAssertTrue(app.staticTexts[
            "Current value available; writing awaits hardware validation"
        ].exists)

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
        XCTAssertTrue(app.staticTexts["setting.status.automaticMedia"].exists)
        let automaticMediaMenu = app.menuButtons[
            "Set value for Automatically pause and resume media"
        ]
        XCTAssertTrue(automaticMediaMenu.waitForExistence(timeout: 3))
        automaticMediaMenu.click()
        let turnOn = automaticMediaMenu.menuItems["Turn On"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 2))
        turnOn.click()
        XCTAssertTrue(app.checkBoxes["Automatically pause and resume media"].waitForExistence(timeout: 2))

        navigate(to: "Noise Control", in: app)
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
        let unknownSmartSwitch = app.staticTexts["setting.unknown.smartSwitch"]
        XCTAssertTrue(unknownSmartSwitch.waitForExistence(timeout: 2))
        XCTAssertEqual(unknownSmartSwitch.label, "Smart Switch")
        XCTAssertEqual(unknownSmartSwitch.value as? String, "Not read from headset")

        let statusItem = app.statusItems["WL5024 connected"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 3))
        statusItem.click()
        XCTAssertTrue(app.menuItems["Automatic media control"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Experimental — response verification required"].exists)
    }

    @MainActor
    func testBluetoothPermissionRecoveryExplainsPrivacyDestination() {
        let app = launch(["--ui-bluetooth-denied"])
        XCTAssertTrue(app.buttons["Open Bluetooth Privacy Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "In System Settings → Privacy & Security → Bluetooth, allow WL5024 Control to use Bluetooth. Then return here and reconnect."
        ].exists)
        XCTAssertFalse(app.buttons["Refresh"].isEnabled)

        app.buttons["Open Bluetooth Privacy Settings"].click()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
        let permissionExplanation = settings.staticTexts.matching(NSPredicate(
            format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
            "Allow", "Allow", "Bluetooth", "Bluetooth"
        )).firstMatch
        XCTAssertTrue(permissionExplanation.waitForExistence(timeout: 10),
                      "The destination must show app permissions for Bluetooth")
        app.activate()
    }

    @MainActor
    func testDiagnosticsSelectableValuesProgressCancellationAndFocusReturn() throws {
        let app = launch([
            "--demo",
            "--ui-fast-discovery",
            "--ui-observe-export-progress",
            "--ui-focus-probe",
        ])
        navigate(to: "Diagnostics", in: app)
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "diagnostics.protocol.value").count, 0)

        let discoveryButton = app.buttons["Run Read-only Discovery"]
        XCTAssertTrue(discoveryButton.waitForExistence(timeout: 2))
        XCTAssertTrue(discoveryButton.isEnabled)
        discoveryButton.click()
        XCTAssertTrue(app.staticTexts["diagnostics.discovery.summary"].waitForExistence(timeout: 3))

        let exportButton = app.buttons["Collect & Export Log…"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(exportButton.isEnabled)
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
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(exportButton.isEnabled)
        exportButton.click()

        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Diagnostic Export"].exists)
        alert.buttons["Done"].click()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Export button focused"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDiscoveryCancellationShowsPartialResult() throws {
        // AUD-011: mock discovery yields so progress renders and Cancel is
        // deliverable mid-run in demo mode.
        let app = launch(["--demo"])
        navigate(to: "Diagnostics", in: app)
        let runButton = app.buttons["Run Read-only Discovery"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 2))
        runButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics.discovery.progress"].waitForExistence(timeout: 2))
        let cancelButton = app.buttons["Cancel Discovery"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.click()
        XCTAssertTrue(app.staticTexts["Discovery cancelled. Partial results remain in the diagnostic log."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchSmokeAcrossAppearanceProfiles() throws {
        // AUD-012: launch smoke only — proves the app starts and exposes one
        // control per appearance profile. Visual legibility, contrast,
        // transparency, clipping, and overlap remain manual checklist items.
        let profiles: [([String], String)] = [
            (["--demo", "--appearance-light"], "Light"),
            (["--demo", "--appearance-dark"], "Dark"),
            (["--demo", "-AppleIncreaseContrast", "YES"], "IncreaseContrast"),
            (["--demo", "-AppleReduceTransparency", "YES"], "ReduceTransparency"),
        ]

        for (arguments, name) in profiles {
            let app = launch(arguments)
            XCTAssertTrue(app.staticTexts["Dell WL5024"].waitForExistence(timeout: 5), "Missing identity in \(name)")
            navigate(to: "Calls & Microphone", in: app)
            XCTAssertTrue(app.popUpButtons["Sidetone"].exists, "Missing Sidetone in \(name)")
            attachScreenshot(named: "LaunchSmoke-\(name)", app: app)
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
