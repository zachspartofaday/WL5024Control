import XCTest

final class WL5024ControlUITests: XCTestCase {
    @MainActor
    func testSingleScreenShowsPersistenceAndAccessSemantics() {
        let app = launch(["--demo", "--ui-login-disabled"])

        XCTAssertTrue(app.descendants(matching: .any)["headsetSettings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.outlines["Settings destinations"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["launchAtLogin.toggle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Off"].exists)

        let wearDetection = app.descendants(matching: .any)["setting.toggle.wearDetection"]
        XCTAssertTrue(scrollTo(wearDetection, in: app))
        XCTAssertTrue(wearDetection.isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["setting.status.wearDetection"].exists)

        let readOnlyValue = app.descendants(matching: .any)["setting.value.autoPowerOff"]
        XCTAssertFalse(readOnlyValue.exists)
        XCTAssertFalse(app.popUpButtons["Automatic power off"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["setting.status.autoPowerOff"].exists)

        attachScreenshot(named: "SingleSettingsScreen", app: app)
    }

    @MainActor
    func testExperimentalAndReadOnlyModesUseStaticValuesWhenNotWritable() {
        let experimental = launch(["--experimental", "--ui-login-disabled"])
        let experimentalMenu = experimental.menuButtons["Set value for Automatically pause and resume media"]
        XCTAssertTrue(scrollTo(experimentalMenu, in: experimental))
        XCTAssertTrue(experimental.buttons["About writable controls"].exists)
        experimental.terminate()

        let readOnly = launch(["--read-only", "--ui-login-disabled"])
        let automaticMediaValue = readOnly.descendants(matching: .any)["setting.value.automaticMedia"]
        XCTAssertTrue(scrollTo(automaticMediaValue, in: readOnly))
        XCTAssertFalse(readOnly.descendants(matching: .any)["setting.toggle.automaticMedia"].exists)
        XCTAssertTrue(readOnly.staticTexts["Read Only"].exists)
    }

    @MainActor
    func testQuickPauseSensitivityExplainsItsDependency() {
        let app = launch(["--demo", "--ui-login-disabled"])
        let quickPause = app.descendants(matching: .any)["setting.toggle.quickPause"]
        XCTAssertTrue(scrollTo(quickPause, in: app))
        quickPause.click()

        let status = app.descendants(matching: .any)["setting.status.quickPauseSensitivity"]
        XCTAssertTrue(scrollTo(status, in: app))
        XCTAssertTrue(app.staticTexts["Requires Quick Pause"].exists)
    }

    @MainActor
    func testDiagnosticsOpensInSeparateUtilityWindow() {
        let app = launch(["--demo", "--ui-fast-discovery", "--ui-login-disabled"])
        app.buttons["Diagnostics"].click()

        let diagnosticsWindow = app.windows["Diagnostics"]
        XCTAssertTrue(diagnosticsWindow.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            diagnosticsWindow.staticTexts.matching(identifier: "diagnostics.protocol.value").count,
            0
        )
        XCTAssertGreaterThanOrEqual(app.windows.count, 2)
    }

    @MainActor
    func testMenuContainsStatusAndWindowActionsButNoSettingsControls() {
        let app = launch(["--demo", "--ui-login-disabled"])
        let statusItem = app.statusItems["WL5024 connected"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 3))
        statusItem.click()

        XCTAssertTrue(app.menuItems["Open Settings…"].exists)
        XCTAssertTrue(app.menuItems["Diagnostics…"].exists)
        XCTAssertTrue(app.menuItems["Refresh"].exists)
        XCTAssertFalse(app.menuItems["Automatic media control"].exists)
        XCTAssertFalse(app.menuItems.matching(NSPredicate(format: "label BEGINSWITH %@", "Automatic media control")).firstMatch.exists)
    }

    @MainActor
    func testLoginLaunchStartsMenuOnlyAndCanOpenSettings() {
        let app = launchRaw(["--demo", "--ui-login-launch", "--ui-login-disabled"])
        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 2))

        let statusItem = app.statusItems["WL5024 connected"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Open Settings…"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testClosingLastWindowLeavesMenuBarItemAvailable() {
        let app = launch(["--demo", "--ui-login-disabled"])
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.statusItems["WL5024 connected"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchAtLoginApprovalIsMacLocalAndActionable() {
        let app = launch(["--demo", "--ui-login-approval"])
        let approval = app.staticTexts["Approval Required"]
        XCTAssertTrue(scrollTo(approval, in: app))
        XCTAssertTrue(app.buttons["Open Login Items…"].exists)
    }

    @MainActor
    func testBluetoothPermissionRecoveryExplainsPrivacyDestination() {
        let app = launch(["--ui-bluetooth-denied", "--ui-login-disabled"])
        XCTAssertTrue(app.buttons["Open Bluetooth Privacy Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "In System Settings → Privacy & Security → Bluetooth, allow WL5024 Control to use Bluetooth. Then return here and reconnect."
        ].exists)
        XCTAssertFalse(app.buttons["Refresh"].isEnabled)
    }

    @MainActor
    func testLaunchSmokeAcrossAppearanceAndSizeProfiles() {
        let profiles: [([String], String)] = [
            (["--demo", "--appearance-light", "--ui-login-disabled"], "Light"),
            (["--demo", "--appearance-dark", "--ui-login-disabled"], "Dark"),
            (["--demo", "--ui-minimum", "--ui-login-disabled"], "Minimum"),
        ]

        for (arguments, name) in profiles {
            let app = launch(arguments)
            XCTAssertTrue(app.descendants(matching: .any)["headsetSettings"].waitForExistence(timeout: 5))
            attachScreenshot(named: "Settings-\(name)", app: app)
            app.terminate()
        }
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = launchRaw(arguments)
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            let connected = app.statusItems["WL5024 connected"]
            let disconnected = app.statusItems["WL5024 disconnected"]
            let statusItem = connected.waitForExistence(timeout: 3) ? connected : disconnected
            XCTAssertTrue(statusItem.exists)
            statusItem.click()
            app.menuItems["Open Settings…"].click()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
        return app
    }

    @MainActor
    private func launchRaw(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3",
        ]
        app.launch()
        addTeardownBlock { @MainActor in
            if app.state != .notRunning { app.terminate() }
        }
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 1), element.isHittable { return true }
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else { return element.exists }
        for _ in 0..<12 {
            if element.exists, element.isHittable { return true }
            scrollView.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
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
