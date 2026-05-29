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

        app.assertElementExists(
            id: AutomationID.Dock.root.rawValue,
            context: "Dock search was visible, but the Dock root hook was missing."
        )
        app.assertElementExists(id: AutomationID.Dock.lensButton(DockLensID.newest.rawValue).rawValue)
        app.assertElementExists(id: AutomationID.Dock.lensButton(DockLensID.host.rawValue).rawValue)
        app.assertElementExists(id: AutomationID.Dock.lensButton(DockLensID.branch.rawValue).rawValue)
        app.assertElementExists(id: AutomationID.Dock.lensPicker.rawValue)
        app.assertElementExists(id: AutomationID.Dock.filterButton.rawValue)
        app.assertElementExists(id: AutomationID.Dock.activeFilterSummary.rawValue)
        XCTAssertFalse(app.element(id: "codexdock.dock.sort").exists)
        XCTAssertFalse(app.element(id: "codexdock.dock.idle-toggle").exists)
        XCTAssertFalse(app.element(id: "codexdock.dock.filter").exists)
        XCTAssertFalse(app.element(id: AutomationID.Connectivity.globalIndicator).stringValue.isEmpty)

        XCTAssertTrue(app.element(id: AutomationID.Dock.root).waitForStringValue(containing: "lens=newest", timeout: 3))
        XCTAssertFalse(app.element(id: AutomationID.Dock.root).stringValue.contains("Limited"))
        XCTAssertFalse(app.element(id: AutomationID.Dock.root).stringValue.contains("Needs me"))
    }

    func testDockLensesAndFiltersAreDrivableInSimulator() throws {
        let app = launchRelayBackedApp()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))
        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(root.waitForStringValue(containing: "lens=newest", timeout: 5))

        app.element(id: AutomationID.Dock.lensButton(DockLensID.host.rawValue)).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "lens=host", timeout: 5))
        XCTAssertNotNil(
            app.waitForElement(identifierPrefix: "codexdock.dock.group.host.", timeout: 10),
            "Host lens did not expose host groups in the iPhone 17 simulator.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        app.element(id: AutomationID.Dock.lensButton(DockLensID.branch.rawValue)).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "lens=branch", timeout: 5))
        XCTAssertNotNil(
            app.waitForElement(identifierPrefix: "codexdock.dock.group.branch.", timeout: 10),
            "Branch lens did not expose branch groups in the iPhone 17 simulator.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        app.element(id: AutomationID.Dock.filterButton).tap()
        app.assertElementExists(id: AutomationID.Dock.filterSurface.rawValue, timeout: 10)
        app.assertElementExists(id: AutomationID.Dock.filterResultSummary.rawValue)
        app.assertElementExists(id: AutomationID.Dock.filterHostAny.rawValue)
        app.assertElementExists(id: AutomationID.Dock.filterBranchSearch.rawValue)
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatusAny, maxSwipes: 3))
        let notLoadedFilterID = AutomationID.Dock.filterStatus(DockRowStatusKind.notLoaded.rawValue).rawValue
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.notLoaded.rawValue), maxSwipes: 3))
        app.element(id: notLoadedFilterID).tap()
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.notLoadedExplanation, maxSwipes: 2))
        let explanation = app.element(id: AutomationID.Dock.notLoadedExplanation).stringValue
        XCTAssertFalse(explanation.localizedCaseInsensitiveContains("rate"))
        XCTAssertFalse(explanation.localizedCaseInsensitiveContains("limit"))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterRepoQuery, maxSwipes: 2))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterSourcePicker, maxSwipes: 2))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterIdleToggle, maxSwipes: 2))
        app.assertElementExists(id: AutomationID.Dock.clearFiltersButton.rawValue)
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

    func assertElementExists(
        id: String,
        timeout: TimeInterval = 5,
        context: String = "Expected simulator UI hook was missing.",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = element(id: id)
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("\(context) Missing id=\(id).\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
        }
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
