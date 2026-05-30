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
        let app = launchRelayBackedApp(
            hosts: "scripted-lenses.local:4510",
            dockStreamScenario: "retention"
        )
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
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.running.rawValue), maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.needsInput.rawValue), maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.needsApproval.rawValue), maxSwipes: 3))
        XCTAssertFalse(app.element(id: AutomationID.Dock.filterStatus("notLoaded")).exists)
        XCTAssertFalse(app.element(id: AutomationID.Dock.filterSurface).stringValue.localizedCaseInsensitiveContains("limited"))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterRepoQuery, maxSwipes: 2))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterSourcePicker, maxSwipes: 2))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterIdleToggle, maxSwipes: 2))
        app.assertElementExists(id: AutomationID.Dock.clearFiltersButton.rawValue)
    }

    func testScriptedDockStreamRetainsRowsThroughStaleGapResyncAndOffline() throws {
        let hosts = "scripted-m5.local:4510,scripted-home.local:4510"
        let app = launchRelayBackedApp(
            hosts: hosts,
            dockStreamScenario: "retention"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForAnyStringValue(containing: ["rows=4", "rows=6"], timeout: 5),
            "Scripted stream did not publish the initial retained rows. Root value: \(root.stringValue)"
        )
        XCTAssertTrue(
            root.waitForStringValue(containing: "rows=6", timeout: 10),
            "Scripted stream did not publish resynced rows. Root value: \(root.stringValue)"
        )
        XCTAssertFalse(root.stringValue.localizedCaseInsensitiveContains("Limited"))
        XCTAssertFalse(app.visibleStaticText("History").exists)
        XCTAssertFalse(app.visibleStaticText("Limited").exists)

        guard let row = app.waitForElement(identifierPrefix: "codexdock.dock.row.", timeout: 5) else {
            XCTFail("Scripted stream did not expose a Dock row.\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }
        XCTAssertFalse(row.stringValue.localizedCaseInsensitiveContains("History"))
        XCTAssertFalse(row.stringValue.localizedCaseInsensitiveContains("Not loaded"))

        app.element(id: AutomationID.Dock.lensButton(DockLensID.host.rawValue)).tap()
        let firstHostID = try DockRelayEndpoint.parse("scripted-m5.local:4510").id
        let hostGroup = app.buttons[AutomationID.Dock.hostGroup("host::\(firstHostID)").rawValue]
        XCTAssertTrue(
            hostGroup.waitForLabel(containing: "Offline", timeout: 10),
            "Scripted stream did not keep host rows visible while reporting offline/stale freshness.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
    }

    func testScriptedDockSwipePinPersistsAcrossLensesRefreshRelaunchAndUnpin() throws {
        let host = "scripted-pin-\(UUID().uuidString.prefix(8)).local:4510"
        let endpoint = try DockRelayEndpoint.parse(host)
        let slug = endpoint.id.map { character in
            character.isLetter || character.isNumber ? String(character) : "-"
        }.joined()
        let threadID = "\(slug)-running"
        let rowID = AutomationID.Dock.row(hostID: endpoint.id, threadID: threadID)
        let pinActionID = AutomationID.Dock.rowAction(hostID: endpoint.id, threadID: threadID, action: .pin)
        let app = launchRelayBackedApp(
            hosts: host,
            dockStreamScenario: "retention"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForAnyStringValue(containing: ["rows=2", "rows=3"], timeout: 10),
            "Scripted stream did not publish rows. Root value: \(root.stringValue)"
        )
        XCTAssertFalse(app.element(id: AutomationID.Dock.pinnedSection).exists)

        XCTAssertTrue(
            app.scrollUntilElementIsInComfortableSwipeArea(id: rowID, maxSwipes: 4),
            "Dock row was not in a stable swipe area before pin. id=\(rowID.rawValue)\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        let row = app.element(id: rowID)
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "Scripted running row did not render.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        app.swipeElementLeft(row)
        let pinButton = app.element(id: pinActionID)
        XCTAssertTrue(
            pinButton.waitForExistence(timeout: 5),
            "Swipe did not expose the row-specific Pin action.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        pinButton.tap()

        XCTAssertTrue(root.waitForStringValue(containing: "pinned=1", timeout: 10))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 10)
        app.assertElementExists(id: AutomationID.Dock.pinnedRowsList.rawValue, timeout: 10)
        app.assertElementExists(id: AutomationID.Dock.pinnedBodyDivider.rawValue, timeout: 5)
        app.assertPinnedDividerGapIsTight(rowID: rowID)
        XCTAssertFalse(app.buttons["Manage"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Show all")).firstMatch.exists)
        XCTAssertTrue(app.element(id: rowID).waitForStringValue(containing: "Pinned", timeout: 5))

        app.element(id: AutomationID.Dock.pinnedToggleButton).tap()
        XCTAssertTrue(app.waitForElementToDisappear(id: AutomationID.Dock.pinnedRowsList, timeout: 5))
        app.element(id: AutomationID.Dock.pinnedToggleButton).tap()
        app.assertElementExists(id: AutomationID.Dock.pinnedRowsList.rawValue, timeout: 5)

        let searchField = app.element(id: AutomationID.Dock.searchField)
        searchField.tap()
        searchField.typeText("no-pinned-match")
        XCTAssertTrue(
            root.waitForStringValue(containing: "pinned=0", timeout: 5),
            "Search did not narrow pinned rows. Root value: \(root.stringValue)"
        )
        XCTAssertTrue(
            app.waitForElementToDisappear(id: AutomationID.Dock.pinnedSection, timeout: 5),
            "Pinned section stayed visible after search excluded the pinned row.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        app.assertElementExists(id: AutomationID.Dock.pinnedHiddenHint.rawValue, timeout: 5)
        app.element(id: AutomationID.Dock.clearSearchButton).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=1", timeout: 5))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 5)
        XCTAssertTrue(app.waitForElementToDisappear(id: AutomationID.Dock.pinnedHiddenHint, timeout: 5))

        app.swipeFirstPinnedCellLeft()
        XCTAssertTrue(
            root.waitForStringValue(containing: "pinned=0", timeout: 10),
            "Inline pinned row did not unpin after swipe.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.waitForElementToDisappear(id: AutomationID.Dock.pinnedSection, timeout: 5),
            "Pinned section stayed visible after inline unpin.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        XCTAssertTrue(
            app.scrollUntilElementIsInComfortableSwipeArea(id: rowID, maxSwipes: 4),
            "Dock row was not in a stable swipe area before repin. id=\(rowID.rawValue)\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        let repinRow = app.element(id: rowID)
        XCTAssertTrue(repinRow.waitForExistence(timeout: 10))
        repinRow.press(forDuration: 0.8)
        let repinButton = app.element(id: pinActionID)
        XCTAssertTrue(
            repinButton.waitForExistence(timeout: 5),
            "Context menu did not expose Pin after inline unpin.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        repinButton.tap()
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=1", timeout: 10))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 10)

        app.element(id: AutomationID.Dock.lensButton(DockLensID.host.rawValue)).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "lens=host", timeout: 5))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 5)

        app.element(id: AutomationID.Dock.lensButton(DockLensID.branch.rawValue)).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "lens=branch", timeout: 5))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 5)

        app.swipeDown()
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=1", timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))
        let relaunchedRoot = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(relaunchedRoot.waitForStringValue(containing: "pinned=1", timeout: 10))
        app.assertElementExists(id: AutomationID.Dock.pinnedSection.rawValue, timeout: 10)

        let relaunchedRow = app.element(id: rowID)
        XCTAssertTrue(relaunchedRow.waitForExistence(timeout: 10))
        app.swipeFirstPinnedCellLeft()

        XCTAssertTrue(
            relaunchedRoot.waitForStringValue(containing: "pinned=0", timeout: 10),
            "Relaunched pinned row did not unpin after swipe.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.waitForElementToDisappear(id: AutomationID.Dock.pinnedSection, timeout: 5),
            "Pinned section stayed visible after unpin.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
    }

    func testScriptedPinnedRowsKeepUserOrderAcrossNativeAndScopedReorder() throws {
        let host = "scripted-order-\(UUID().uuidString.prefix(8)).local:4510"
        let endpoint = try DockRelayEndpoint.parse(host)
        let slug = endpoint.id.map { character in
            character.isLetter || character.isNumber ? String(character) : "-"
        }.joined()
        let alpha = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-alpha")
        let bravo = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-bravo")
        let charlie = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-charlie")
        let delta = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-delta")
        let app = launchRelayBackedApp(
            hosts: host,
            dockStreamScenario: "pinnedOrder"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForStringValue(containing: "rows=4", timeout: 10),
            "Scripted order stream did not publish rows. Root value: \(root.stringValue)"
        )

        app.pinDockRow(rowID: alpha, threadID: "\(slug)-alpha", endpoint: endpoint)
        app.pinDockRow(rowID: bravo, threadID: "\(slug)-bravo", endpoint: endpoint)
        app.pinDockRow(rowID: charlie, threadID: "\(slug)-charlie", endpoint: endpoint)
        app.pinDockRow(rowID: delta, threadID: "\(slug)-delta", endpoint: endpoint)
        app.scrollDockToTop()
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=4", timeout: 10))
        XCTAssertTrue(app.waitForPinnedOrder([alpha, bravo, charlie, delta], timeout: 5))

        app.dragPinnedCell(fromIndex: 2, toIndex: 0)
        XCTAssertTrue(
            app.waitForPinnedOrder([charlie, alpha, bravo, delta], timeout: 10),
            "Native reorder did not move Charlie above Alpha.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        app.swipeDown()
        XCTAssertTrue(app.waitForPinnedOrder([charlie, alpha, bravo, delta], timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))
        XCTAssertTrue(app.waitForPinnedOrder([charlie, alpha, bravo, delta], timeout: 10))

        let searchField = app.element(id: AutomationID.Dock.searchField)
        searchField.tap()
        searchField.typeText("visible")
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=2", timeout: 5))
        XCTAssertTrue(app.waitForPinnedOrder([charlie, alpha], timeout: 5))

        app.dragPinnedCell(fromIndex: 1, toIndex: 0)
        XCTAssertTrue(app.waitForPinnedOrder([alpha, charlie], timeout: 10))

        app.element(id: AutomationID.Dock.clearSearchButton).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "pinned=4", timeout: 5))
        XCTAssertTrue(
            app.waitForPinnedOrder([alpha, charlie, bravo, delta], timeout: 10),
            "Scoped reorder did not preserve hidden pinned rows after clearing search.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
    }

    func testScriptedDockCardsUseTrueMessagesForPreviewOrderAndDetailFilter() throws {
        let host = "scripted-noise-\(UUID().uuidString.prefix(8)).local:4510"
        let endpoint = try DockRelayEndpoint.parse(host)
        let slug = endpoint.id.map { character in
            character.isLetter || character.isNumber ? String(character) : "-"
        }.joined()
        let newer = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-newer-message")
        let noisy = AutomationID.Dock.row(hostID: endpoint.id, threadID: "\(slug)-noise")
        let app = launchRelayBackedApp(
            hosts: host,
            dockStreamScenario: "messageNoise"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForStringValue(containing: "rows=2", timeout: 10),
            "Scripted message-noise stream did not publish rows. Root value: \(root.stringValue)"
        )
        XCTAssertTrue(
            app.waitForRowOrder([newer, noisy], timeout: 10),
            "A row with newer non-message activity moved above a row with a newer true message.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertTrue(app.staticTexts["Stable true message before tool noise."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["TOOL OUTPUT SHOULD NOT DISPLAY"].exists)
        XCTAssertFalse(app.staticTexts["INTERNAL REASONING SHOULD NOT DISPLAY"].exists)

        let noisyRow = app.element(id: noisy)
        XCTAssertTrue(noisyRow.waitForExistence(timeout: 5))
        noisyRow.tap()

        XCTAssertNotNil(app.waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Session.messageFilter).waitForStringValue(containing: "messages", timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Session.messageList).waitForStringValue(containing: "events=1", timeout: 10))
        XCTAssertTrue(app.staticTexts["Stable true message before tool noise."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["TOOL OUTPUT SHOULD NOT DISPLAY"].exists)
        XCTAssertFalse(app.staticTexts["INTERNAL REASONING SHOULD NOT DISPLAY"].exists)
    }

    func testScriptedDormantRowDetailDoesNotShowNotLoadedStatus() throws {
        let app = launchRelayBackedApp(
            hosts: "scripted-m5.local:4510",
            dockStreamScenario: "retention"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForAnyStringValue(containing: ["rows=2", "rows=3"], timeout: 5),
            "Scripted stream did not publish rows. Root value: \(root.stringValue)"
        )

        let dormantRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Scripted background"))
            .firstMatch
        XCTAssertTrue(
            dormantRow.waitForExistence(timeout: 10),
            "Scripted dormant row did not render.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertFalse(dormantRow.stringValue.localizedCaseInsensitiveContains("Not loaded"))

        dormantRow.tap()
        XCTAssertNotNil(app.waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Session.header).waitForExistence(timeout: 10))
        XCTAssertFalse(app.element(id: AutomationID.Session.header).stringValue.localizedCaseInsensitiveContains("Not loaded"))
        XCTAssertFalse(app.element(id: AutomationID.Session.statusPill).exists)
    }

    func testScriptedDockStreamResyncsSchemaMismatch() throws {
        let hosts = "scripted-m5.local:4510,scripted-home.local:4510"
        let app = launchRelayBackedApp(
            hosts: hosts,
            dockStreamScenario: "schemaMismatch"
        )
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        let root = app.element(id: AutomationID.Dock.root)
        XCTAssertTrue(
            root.waitForAnyStringValue(containing: ["rows=4", "rows=6"], timeout: 5),
            "Scripted schema stream did not publish initial rows. Root value: \(root.stringValue)"
        )
        XCTAssertTrue(
            root.waitForStringValue(containing: "rows=6", timeout: 10),
            "Scripted schema mismatch did not resync to the expected row count. Root value: \(root.stringValue)"
        )

        let recoveredRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Scripted schema recovered"))
            .firstMatch
        XCTAssertTrue(
            recoveredRow.waitForExistence(timeout: 10),
            "Scripted schema mismatch did not render a recovered row.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertFalse(root.stringValue.localizedCaseInsensitiveContains("Limited"))
        XCTAssertFalse(app.visibleStaticText("History").exists)
        XCTAssertFalse(app.visibleStaticText("Limited").exists)
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

        guard let row = app.waitForVisibleButton(
            identifierPrefix: "codexdock.dock.row.",
            excludedIdentifierParts: [".action.", ".actions"],
            timeout: 25
        ) else {
            XCTFail("No relay-backed Dock row was available in the iPhone 17 simulator; live Dock-to-detail ID proof needs at least one real session row from the UI test CODEX_DOCK_HOSTS relay list.")
            return
        }

        XCTAssertTrue(
            app.tapVisibleButton(id: row.identifier, timeout: 10),
            "Relay-backed Dock row disappeared or stopped being visibly tappable before tap. id=\(row.identifier)\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        XCTAssertTrue(app.waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 15) != nil)
        XCTAssertTrue(app.element(id: AutomationID.Session.header).waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Session.messageFilter).waitForStringValue(containing: "messages", timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Composer.root).exists)
        let messageField = app.element(id: AutomationID.Composer.messageField)
        XCTAssertTrue(messageField.exists)
        messageField.tap()
        messageField.typeText("UI smoke")
        XCTAssertTrue(app.element(id: AutomationID.Composer.sendButton).waitForExistence(timeout: 5))
    }

    private func launchRelayBackedApp(
        hosts: String? = nil,
        dockStreamScenario: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
            ?? ProcessInfo.processInfo.environment["CODEX_DOCK_UI_TEST_HOSTS"]
            ?? "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
        if let dockStreamScenario {
            app.launchEnvironment["CODEX_DOCK_UI_DOCK_STREAM_SCENARIO"] = dockStreamScenario
        }
        app.terminate()
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

    func waitForElementToDisappear(id: AutomationID, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element(id: id).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !element(id: id).exists
    }

    func swipeFirstPinnedCellLeft(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cell = collectionViews[AutomationID.Dock.pinnedRowsList.rawValue].cells.firstMatch
        guard cell.waitForExistence(timeout: 5) else {
            XCTFail("Pinned collection cell was missing.\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }
        for _ in 0..<3 {
            let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
            let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            start.press(forDuration: 0.18, thenDragTo: end)
            let unpinButton = buttons["Unpin"].firstMatch
            if unpinButton.waitForExistence(timeout: 0.8) {
                unpinButton.tap()
                return
            }
            if !collectionViews[AutomationID.Dock.pinnedRowsList.rawValue].exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func assertPinnedDividerGapIsTight(
        rowID: AutomationID,
        maxGap: CGFloat = 32,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = element(id: rowID)
        let divider = element(id: AutomationID.Dock.pinnedBodyDivider)
        guard row.waitForExistence(timeout: timeout),
              divider.waitForExistence(timeout: timeout) else {
            XCTFail(
                "Pinned row or divider was missing before gap check. rowID=\(rowID.rawValue)\n\nAccessibility tree:\n\(debugDescription)",
                file: file,
                line: line
            )
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastGap = CGFloat.greatestFiniteMagnitude
        while Date() < deadline {
            lastGap = divider.frame.minY - row.frame.maxY
            if lastGap <= maxGap {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "Pinned row left \(lastGap)pt before the divider; expected <= \(maxGap)pt. rowFrame=\(row.frame) dividerFrame=\(divider.frame)",
            file: file,
            line: line
        )
    }

    func pinDockRow(
        rowID: AutomationID,
        threadID: String,
        endpoint: DockRelayEndpoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            scrollUntilElementIsInComfortableSwipeArea(id: rowID, maxSwipes: 8),
            "Dock row was missing, not hittable, or too close to a screen edge before pin. id=\(rowID.rawValue)\n\nAccessibility tree:\n\(debugDescription)",
            file: file,
            line: line
        )
        let row = element(id: rowID)
        swipeElementLeft(row)
        let pinAction = AutomationID.Dock.rowAction(hostID: endpoint.id, threadID: threadID, action: .pin)
        let pinButton = element(id: pinAction)
        XCTAssertTrue(
            pinButton.waitForExistence(timeout: 5),
            "Swipe did not expose Pin for row id=\(rowID.rawValue).\n\nAccessibility tree:\n\(debugDescription)",
            file: file,
            line: line
        )
        pinButton.tap()
    }

    func scrollDockToTop(maxSwipes: Int = 4) {
        for _ in 0..<maxSwipes {
            swipeDown()
        }
    }

    func scrollUntilElementIsInComfortableSwipeArea(id: AutomationID, maxSwipes: Int) -> Bool {
        for _ in 0...maxSwipes {
            let candidate = element(id: id)
            if candidate.waitForExistence(timeout: 1), isVisibleForTap(candidate.frame) {
                if isComfortableSwipeFrame(candidate.frame) {
                    return true
                }
                if shouldScrollUp(toExpose: candidate.frame) {
                    swipeUp()
                } else {
                    swipeDown()
                }
            } else {
                swipeUp()
            }
        }
        return false
    }

    func tapVisibleButton(id: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "identifier == %@", id)
        let query = descendants(matching: .any).matching(predicate)
        while Date() < deadline {
            if query.firstMatch.waitForExistence(timeout: 1) {
                for index in 0..<20 {
                    let element = query.element(boundBy: index)
                    guard element.exists else {
                        break
                    }
                    if isVisibleForTap(element.frame) {
                        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        return true
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func swipeElementLeft(_ element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func isComfortableSwipeFrame(_ frame: CGRect) -> Bool {
        let visibleFrame = primaryWindowFrame(defaultingTo: frame)
        let topInset: CGFloat = 96
        let bottomLimit = tabBars.firstMatch.exists
            ? tabBars.firstMatch.frame.minY - 12
            : visibleFrame.maxY - 96
        return frame.minY >= visibleFrame.minY + topInset
            && frame.maxY <= bottomLimit
    }

    private func shouldScrollUp(toExpose frame: CGRect) -> Bool {
        frame.midY >= primaryWindowFrame(defaultingTo: frame).midY
    }

    private func isVisibleForTap(_ frame: CGRect) -> Bool {
        guard frame.width > 1, frame.height > 1 else {
            return false
        }
        let visibleFrame = primaryWindowFrame(defaultingTo: frame)
        let bottomLimit = tabBars.firstMatch.exists
            ? tabBars.firstMatch.frame.minY - 1
            : visibleFrame.maxY - 1
        return frame.midY >= visibleFrame.minY + 1
            && frame.midY <= bottomLimit
            && frame.maxX > visibleFrame.minX
            && frame.minX < visibleFrame.maxX
    }

    private func primaryWindowFrame(defaultingTo frame: CGRect) -> CGRect {
        let window = windows.firstMatch
        return window.exists ? window.frame : frame
    }

    func scrollUntilElementIsHittable(id: AutomationID, maxSwipes: Int) -> Bool {
        if element(id: id).waitForExistence(timeout: 1), isVisibleForTap(element(id: id).frame) {
            return true
        }
        for _ in 0..<maxSwipes {
            swipeUp()
            let candidate = element(id: id)
            if candidate.waitForExistence(timeout: 1), isVisibleForTap(candidate.frame) {
                return true
            }
        }
        return false
    }

    func dragPinnedCell(
        fromIndex sourceIndex: Int,
        toIndex destinationIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cells = collectionViews[AutomationID.Dock.pinnedRowsList.rawValue].cells
        let source = cells.element(boundBy: sourceIndex)
        let destination = cells.element(boundBy: destinationIndex)
        guard source.waitForExistence(timeout: 5), destination.waitForExistence(timeout: 5) else {
            XCTFail("Pinned cells were missing for reorder.\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        start.press(forDuration: 0.85, thenDragTo: end)
    }

    func waitForPinnedOrder(_ rowIDs: [AutomationID], timeout: TimeInterval) -> Bool {
        waitForRowOrder(rowIDs, timeout: timeout)
    }

    func waitForRowOrder(_ rowIDs: [AutomationID], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let rows = rowIDs.map { element(id: $0) }
            if rows.allSatisfy(\.exists) {
                let yPositions = rows.map { $0.frame.minY }
                if zip(yPositions, yPositions.dropFirst()).allSatisfy({ $0 <= $1 }) {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    func waitForVisibleButton(
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
                if isVisibleForTap(element.frame) {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func visibleStaticText(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
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

    func waitForAnyStringValue(containing expectedValues: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if expectedValues.contains(where: { stringValue.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    func waitForLabel(containing expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if label.contains(expected) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
