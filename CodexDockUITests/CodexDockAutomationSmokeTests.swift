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
        XCTAssertFalse(app.element(id: AutomationID.Dock.activeFilterSummary).stringValue.contains("Idle hidden"))
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

        app.element(id: AutomationID.Dock.lensButton(DockLensID.branch.rawValue)).tap()
        XCTAssertTrue(root.waitForStringValue(containing: "lens=branch", timeout: 5))

        app.element(id: AutomationID.Dock.filterButton).tap()
        app.assertElementExists(id: AutomationID.Dock.filterSurface.rawValue, timeout: 10)
        app.assertElementExists(id: AutomationID.Dock.filterResultSummary.rawValue)
        XCTAssertFalse(app.element(id: AutomationID.Dock.filterResultSummary).stringValue.contains("Idle hidden"))
        app.assertElementExists(id: AutomationID.Dock.filterHostAny.rawValue)
        app.assertElementExists(id: AutomationID.Dock.filterBranchSearch.rawValue)
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatusAny, maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.running.rawValue), maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.needsInput.rawValue), maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.needsApproval.rawValue), maxSwipes: 3))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterStatus(DockRowStatusKind.idle.rawValue), maxSwipes: 3))
        XCTAssertFalse(app.element(id: AutomationID.Dock.filterStatus("notLoaded")).exists)
        XCTAssertFalse(app.element(id: AutomationID.Dock.filterSurface).stringValue.localizedCaseInsensitiveContains("limited"))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterRepoQuery, maxSwipes: 2))
        XCTAssertTrue(app.scrollUntilElementExists(id: AutomationID.Dock.filterSourcePicker, maxSwipes: 2))
        app.assertElementExists(id: AutomationID.Dock.clearFiltersButton.rawValue)
    }

    func testRelaySettingsFormIsDrivableByIdentifier() throws {
        let app = launchRelayBackedApp()
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))

        app.openTaskSheet(.relaySettings)

        XCTAssertTrue(app.element(id: AutomationID.Relay.root).waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(id: AutomationID.Relay.testAllButton).exists)
        XCTAssertTrue(app.element(id: AutomationID.Relay.addButton).exists)
        XCTAssertFalse(app.element(id: AutomationID.Relay.editor).exists)
        app.element(id: AutomationID.Relay.addButton).tap()
        XCTAssertTrue(app.element(id: AutomationID.Relay.editor).waitForExistence(timeout: 5))
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

    private func launchRelayBackedApp(hosts: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
            ?? ProcessInfo.processInfo.environment["CODEX_DOCK_UI_TEST_HOSTS"]
            ?? "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
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

    func openTaskSheet(_ sheet: DockTaskSheet) {
        let menuCandidates = [
            AutomationID.TaskSheet.menuItem(sheet).rawValue,
            sheet.menuLabel,
        ]

        for candidate in menuCandidates {
            guard openTaskSheetMenu() else {
                return
            }
            let button = buttons[candidate].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                if waitForTaskSheet(sheet, timeout: 5) {
                    return
                }
            }
        }

        XCTFail(
            "Dock task sheet \(sheet.rawValue) did not open from More. Expected root id=\(sheet.expectedRootID.rawValue).\n\nAccessibility tree:\n\(debugDescription)"
        )
    }

    private func openTaskSheetMenu(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let moreButton = element(id: AutomationID.TaskSheet.moreButton)
        guard moreButton.waitForExistence(timeout: 5) else {
            XCTFail(
                "Dock More menu was missing.\n\nAccessibility tree:\n\(debugDescription)",
                file: file,
                line: line
            )
            return false
        }
        moreButton.tap()
        return true
    }

    private func waitForTaskSheet(_ sheet: DockTaskSheet, timeout: TimeInterval) -> Bool {
        let rootID = sheet.expectedRootID
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element(id: rootID).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element(id: rootID).exists
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

private extension DockTaskSheet {
    var menuLabel: String {
        switch self {
        case .archiveCleanup:
            return "Archive cleanup"
        case .archivedThreads:
            return "Archived threads"
        case .systemHealth:
            return "System health"
        case .relaySettings:
            return "Relay settings"
        }
    }

    var expectedRootID: AutomationID {
        switch self {
        case .archiveCleanup:
            return AutomationID.ArchiveCleanup.root
        case .archivedThreads:
            return AutomationID.Archive.root
        case .systemHealth:
            return AutomationID.SystemHealth.root
        case .relaySettings:
            return AutomationID.Relay.root
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
