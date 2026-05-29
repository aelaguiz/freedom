import CodexDock
import XCTest

@MainActor
final class CodexDockAutomationSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDockScreenExposesControlsAndConnectivityByIdentifier() throws {
        let app = launchRelayBackedApp()
        let start = app.waitForFirstIdentifier([
            AutomationID.Dock.searchField.rawValue,
            AutomationID.Bootstrap.manualHostField.rawValue,
        ], timeout: 20)

        guard start == AutomationID.Dock.searchField.rawValue else {
            XCTAssertEqual(start, AutomationID.Bootstrap.manualHostField.rawValue)
            XCTAssertTrue(app.element(id: AutomationID.Bootstrap.root).exists)
            XCTAssertTrue(app.element(id: AutomationID.Bootstrap.manualPortField).exists)
            XCTAssertTrue(app.element(id: AutomationID.Bootstrap.manualConnectButton).exists)
            XCTAssertFalse(app.element(id: AutomationID.Connectivity.globalIndicator).stringValue.isEmpty)
            return
        }

        XCTAssertTrue(app.element(id: AutomationID.Dock.root).exists)
        XCTAssertTrue(app.element(id: AutomationID.Dock.sortPicker).exists)
        XCTAssertTrue(app.element(id: AutomationID.Dock.idleToggle).exists)
        XCTAssertFalse(app.element(id: AutomationID.Connectivity.globalIndicator).stringValue.isEmpty)

        let idleToggle = app.element(id: AutomationID.Dock.idleToggle)
        idleToggle.tap()
        XCTAssertTrue(idleToggle.waitForStringValue(containing: "On", timeout: 3))
    }

    func testRelaySettingsFormIsDrivableByIdentifier() throws {
        let app = launchRelayBackedApp()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        app.tapRootTab(.relay)

        XCTAssertTrue(app.element(id: AutomationID.Relay.root).waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Relay.testAllButton).exists)
        XCTAssertTrue(app.element(id: AutomationID.Relay.editor).exists)
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Relay.hostField, maxSwipes: 3))
        XCTAssertTrue(app.element(id: AutomationID.Relay.hostField).exists)
        XCTAssertTrue(app.element(id: AutomationID.Relay.portField).exists)
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Relay.saveButton, maxSwipes: 3))
        XCTAssertTrue(app.element(id: AutomationID.Relay.saveButton).exists)

        let hostField = app.element(id: AutomationID.Relay.hostField)
        hostField.tap()
        XCTAssertTrue(hostField.exists)
    }

    func testDockRowOpensSessionDetailByIdentifierWhenRowsExist() throws {
        let app = launchRelayBackedApp()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))
        app.tapDockFilterTab(.agents)

        guard let row = app.waitForHittableButton(
            identifierPrefix: "codexdock.dock.row.",
            excludedIdentifierParts: [".action.", ".actions"],
            timeout: 25
        ) else {
            XCTFail("No relay-backed Dock row was available in the iPhone 17 simulator; live Dock-to-detail ID proof needs at least one real session row from the UI test CODEX_DOCK_HOSTS relay list.")
            return
        }

        row.tap()
        XCTAssertTrue(app.waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 15) != nil)
        XCTAssertTrue(app.element(id: AutomationID.Session.header).waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Session.messageFilter).exists)
        XCTAssertTrue(app.element(id: AutomationID.Composer.root).exists)
        let messageField = app.element(id: AutomationID.Composer.messageField)
        XCTAssertTrue(messageField.exists)
        messageField.tap()
        messageField.typeText("UI smoke")
        XCTAssertTrue(app.element(id: AutomationID.Composer.sendButton).waitForExistence(timeout: 5))
    }

    private func launchRelayBackedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = ProcessInfo.processInfo.environment["CODEX_DOCK_UI_TEST_HOSTS"]
            ?? "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
        app.launch()
        return app
    }
}

@MainActor
private extension XCUIApplication {
    func element(id: AutomationID) -> XCUIElement {
        element(id: id.rawValue)
    }

    func element(id: String) -> XCUIElement {
        descendants(matching: .any)[id]
    }

    func waitForFirstIdentifier(_ identifiers: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers where element(id: identifier).exists {
                return identifier
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    func waitForElement(
        identifierPrefix: String,
        excludedIdentifierParts: [String] = [],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = firstElement(
                identifierPrefix: identifierPrefix,
                excludedIdentifierParts: excludedIdentifierParts
            ) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    private func firstElement(
        identifierPrefix: String,
        excludedIdentifierParts: [String]
    ) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let element = descendants(matching: .any).matching(predicate).firstMatch
        guard element.exists else {
            return nil
        }
        guard !excludedIdentifierParts.contains(where: { element.identifier.contains($0) }) else {
            return nil
        }
        return element
    }

    func tapRootTab(_ tab: AutomationID.RootTab) {
        let tabIDElement = element(id: AutomationID.Root.tab(tab))
        if tabIDElement.waitForExistence(timeout: 2) {
            tabIDElement.tap()
            return
        }

        let fallbackButton = tabBars.buttons[tab.platformTabLabel]
        XCTAssertTrue(
            fallbackButton.waitForExistence(timeout: 5),
            "SwiftUI did not expose \(AutomationID.Root.tab(tab).rawValue); falling back to the platform tab bar label for \(tab.platformTabLabel)."
        )
        fallbackButton.tap()
    }

    func tapDockFilterTab(_ tab: DockTabID) {
        let tabElement = element(id: AutomationID.Dock.filterTab(tab.rawValue))
        if tabElement.waitForExistence(timeout: 2) {
            tabElement.tap()
            return
        }

        let picker = element(id: AutomationID.Dock.filterPicker)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let tabIndex = DockTabID.allCases.firstIndex(of: tab) ?? 0
        let segment = picker.buttons.element(boundBy: tabIndex)
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.tap()
    }

    func scrollUntilElementExists(id: AutomationID, maxSwipes: Int) -> Bool {
        if element(id: id).waitForExistence(timeout: 1) {
            return true
        }
        for _ in 0..<maxSwipes {
            swipeUp()
            if element(id: id).waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }

    func waitForHittableButton(
        identifierPrefix: String,
        excludedIdentifierParts: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let query = buttons.matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for index in 0..<30 {
                let element = query.element(boundBy: index)
                guard element.exists else {
                    break
                }
                guard !excludedIdentifierParts.contains(where: { element.identifier.contains($0) }) else {
                    continue
                }
                if element.isHittable {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }
}

private extension AutomationID.RootTab {
    var platformTabLabel: String {
        switch self {
        case .dock:
            return "Dock"
        case .archive:
            return "Archive"
        case .relay:
            return "Relay"
        }
    }
}

@MainActor
private extension XCUIElement {
    var stringValue: String {
        if let value = self.value as? String {
            return value
        }
        return label
    }

    func waitForStringValue(containing expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if stringValue.contains(expected) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
