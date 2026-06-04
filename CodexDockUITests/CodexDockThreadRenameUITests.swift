import CodexDock
import XCTest

@MainActor
final class CodexDockThreadRenameUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testRealThreadRenameRoundTripWhenConfigured() throws {
        let config = try ThreadRenameProofConfig.loadFromEnvironment()
        let app = launchRelayBackedApp(hosts: config.hosts)
        XCTAssertTrue(app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.element(id: AutomationID.Dock.root).waitForDisplayedUIStringValue(containing: "loaded;", timeout: 30),
            "Dock did not reach loaded state before rename proof.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        app.collapsePinnedSectionIfExpandedForRenameProof()
        var activeProofTitle: String?
        defer {
            if let activeProofTitle {
                if app.element(id: AutomationID.Session.renameButton).exists {
                    app.renameOpenDetailThreadThroughToolbar(config: config, newTitle: config.originalTitle)
                } else if let row = app.findDockRowForRenameProof(config: config, title: activeProofTitle, timeout: 10) {
                    app.renameDockRowThroughSheet(row: row, config: config, newTitle: config.originalTitle)
                }
            }
        }

        guard let originalRow = app.findDockRowForRenameProof(
            config: config,
            title: config.originalTitle,
            timeout: 30
        ) else {
            XCTFail("Rename proof could not find original row host=\(config.hostID) thread=\(config.threadID) title=\(config.originalTitle).\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }

        app.renameDockRowThroughSheet(
            row: originalRow,
            config: config,
            newTitle: config.proofTitle
        )
        activeProofTitle = config.proofTitle

        guard let renamedRow = app.findDockRowForRenameProof(
            config: config,
            title: config.proofTitle,
            timeout: 30
        ) else {
            XCTFail("Rename proof did not observe the new title \(config.proofTitle) in the real Dock row.\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }

        app.renameDockRowThroughSheet(
            row: renamedRow,
            config: config,
            newTitle: config.originalTitle
        )

        guard app.findDockRowForRenameProof(
            config: config,
            title: config.originalTitle,
            timeout: 30
        ) != nil else {
            XCTFail("Rename proof did not observe the restored title \(config.originalTitle) in the real Dock row.\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }
        activeProofTitle = nil

        guard let detailRow = app.findDockRowForRenameProof(
            config: config,
            title: config.originalTitle,
            timeout: 30
        ) else {
            XCTFail("Rename proof could not refind restored row before detail-toolbar proof.\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }
        detailRow.tap()
        XCTAssertNotNil(
            app.waitForLoadedSessionRootForRenameProof(config: config, timeout: 30),
            "Rename proof opened the real row, but Thread Detail never reached loaded state.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        app.renameOpenDetailThreadThroughToolbar(config: config, newTitle: config.detailProofTitle)
        activeProofTitle = config.detailProofTitle
        XCTAssertTrue(
            app.waitForVisibleStaticText(config.detailProofTitle, timeout: 30),
            "Thread Detail did not show detail-toolbar proof title \(config.detailProofTitle).\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        app.renameOpenDetailThreadThroughToolbar(config: config, newTitle: config.originalTitle)
        XCTAssertTrue(
            app.waitForVisibleStaticText(config.originalTitle, timeout: 30),
            "Thread Detail did not show restored title \(config.originalTitle).\n\nAccessibility tree:\n\(app.debugDescription)"
        )
        activeProofTitle = nil
        app.navigateBackToDockForRenameProof()
        XCTAssertNotNil(
            app.findDockRowForRenameProof(config: config, title: config.originalTitle, timeout: 30),
            "Rename proof did not observe restored title in Dock after returning from Thread Detail.\n\nAccessibility tree:\n\(app.debugDescription)"
        )
    }

    private func launchRelayBackedApp(hosts: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
            ?? ProcessInfo.processInfo.environment["CODEX_DOCK_UI_TEST_HOSTS"]
            ?? "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
        app.launch()
        return app
    }
}

private struct ThreadRenameProofConfig {
    let hostID: String
    let threadID: String
    let originalTitle: String
    let proofTitle: String
    let detailProofTitle: String
    let hosts: String?

    static func loadFromEnvironment() throws -> ThreadRenameProofConfig {
        let environment = ProcessInfo.processInfo.environment
        guard let hostID = nonEmpty(environment["CODEX_DOCK_RENAME_PROOF_HOST_ID"]),
              let threadID = nonEmpty(environment["CODEX_DOCK_RENAME_PROOF_THREAD_ID"]),
              let originalTitle = nonEmpty(environment["CODEX_DOCK_RENAME_PROOF_ORIGINAL_TITLE"]) else {
            throw XCTSkip("Set CODEX_DOCK_RENAME_PROOF_HOST_ID, CODEX_DOCK_RENAME_PROOF_THREAD_ID, and CODEX_DOCK_RENAME_PROOF_ORIGINAL_TITLE to run the real-thread rename UI proof.")
        }

        let proofTitle = nonEmpty(environment["CODEX_DOCK_RENAME_PROOF_NEW_TITLE"])
            ?? "Codex Dock Rename Proof \(Int(Date().timeIntervalSince1970))"
        let detailProofTitle = nonEmpty(environment["CODEX_DOCK_RENAME_PROOF_DETAIL_TITLE"])
            ?? "\(proofTitle) Detail"
        return ThreadRenameProofConfig(
            hostID: hostID,
            threadID: threadID,
            originalTitle: originalTitle,
            proofTitle: proofTitle,
            detailProofTitle: detailProofTitle,
            hosts: nonEmpty(environment["CODEX_DOCK_UI_TEST_HOSTS"])
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

@MainActor
private extension XCUIApplication {
    func element(id: AutomationID) -> XCUIElement {
        descendants(matching: .any)[id.rawValue]
    }

    func findDockRowForRenameProof(
        config: ThreadRenameProofConfig,
        title: String,
        timeout: TimeInterval
    ) -> XCUIElement? {
        guard setDockSearchText(title, timeout: 10) else {
            return nil
        }

        let identifier = AutomationID.Dock.row(hostID: config.hostID, threadID: config.threadID).rawValue
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = largestVisibleElement(exactIdentifier: identifier),
               row.label.localizedCaseInsensitiveContains(title) {
                return row
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func renameDockRowThroughSheet(
        row: XCUIElement,
        config: ThreadRenameProofConfig,
        newTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        row.press(forDuration: 0.8)

        let actionID = AutomationID.Dock.rowAction(
            hostID: config.hostID,
            threadID: config.threadID,
            action: .rename
        )
        let renameAction = element(id: actionID)
        if renameAction.waitForExistence(timeout: 2) {
            renameAction.tap()
        } else {
            let fallback = buttons["Rename"].firstMatch
            guard fallback.waitForExistence(timeout: 2) else {
                XCTFail("Rename action did not appear for row \(row.identifier).\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
                return
            }
            fallback.tap()
        }

        submitRenameSheet(newTitle: newTitle, file: file, line: line)
    }

    func renameOpenDetailThreadThroughToolbar(
        config: ThreadRenameProofConfig,
        newTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renameButton = element(id: AutomationID.Session.renameButton)
        guard renameButton.waitForExistence(timeout: 5) else {
            XCTFail("Thread Detail rename button was missing.\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }
        renameButton.tap()
        submitRenameSheet(newTitle: newTitle, file: file, line: line)
    }

    func submitRenameSheet(
        newTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sheet = element(id: AutomationID.Dock.renameSheet)
        guard sheet.waitForExistence(timeout: 5) else {
            XCTFail("Rename sheet did not open.\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }

        let field = element(id: AutomationID.Dock.renameNameField)
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Rename name field was missing.\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 160))
        field.typeText(newTitle)

        let saveButton = element(id: AutomationID.Dock.renameSaveButton)
        guard waitForEnabledElement(saveButton, timeout: 5) else {
            XCTFail("Rename save button did not become enabled for \(newTitle).\n\nAccessibility tree:\n\(debugDescription)", file: file, line: line)
            return
        }
        saveButton.tap()

        XCTAssertTrue(
            waitForElementToDisappear(id: AutomationID.Dock.renameSheet, timeout: 15),
            "Rename sheet did not dismiss after saving \(newTitle).\n\nAccessibility tree:\n\(debugDescription)",
            file: file,
            line: line
        )
    }

    func waitForLoadedSessionRootForRenameProof(
        config: ThreadRenameProofConfig,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let root = element(id: AutomationID.Session.root(threadID: config.threadID))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if root.exists, root.displayedUIStringValue.contains("loaded;") {
                return root
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func waitForVisibleStaticText(_ title: String, timeout: TimeInterval) -> Bool {
        let text = staticTexts[title].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text.exists, isVisibleForTapForRenameProof(text.frame) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return text.exists && isVisibleForTapForRenameProof(text.frame)
    }

    func navigateBackToDockForRenameProof() {
        if element(id: AutomationID.Dock.root).exists {
            return
        }
        let backButton = navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
        }
        _ = element(id: AutomationID.Dock.root).waitForExistence(timeout: 10)
    }

    func collapsePinnedSectionIfExpandedForRenameProof() {
        let toggle = element(id: AutomationID.Dock.pinnedToggleButton)
        guard toggle.waitForExistence(timeout: 2),
              element(id: AutomationID.Dock.pinnedRowsList).exists else {
            return
        }
        toggle.tap()
        _ = waitForElementToDisappear(id: AutomationID.Dock.pinnedRowsList, timeout: 3)
    }

    func waitForElementToDisappear(id: AutomationID, timeout: TimeInterval) -> Bool {
        let element = element(id: id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !element.exists
    }

    func waitForEnabledElement(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists && element.isEnabled
    }

    func largestVisibleElement(exactIdentifier identifier: String) -> XCUIElement? {
        descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .allElementsBoundByIndex
            .filter { isVisibleForTapForRenameProof($0.frame) }
            .max { left, right in
                (left.frame.width * left.frame.height) < (right.frame.width * right.frame.height)
            }
    }

    func isVisibleForTapForRenameProof(_ frame: CGRect) -> Bool {
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

    func primaryWindowFrame(defaultingTo frame: CGRect) -> CGRect {
        let window = windows.firstMatch
        return window.exists ? window.frame : frame
    }
}
