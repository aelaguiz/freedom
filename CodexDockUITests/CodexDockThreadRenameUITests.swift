import CodexDock
import Foundation
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

    func testControlledClientRenameIsOptimisticWhenConfigured() throws {
        let config = try ClientRenameLatencyProofConfig.loadFromEnvironment()
        let startedAt = codexDockISO8601Now()
        let app = launchRelayBackedApp(hosts: config.hosts)

        func writeResult(
            status: DisplayedUIArtifactStatus,
            reason: String?,
            timings: ClientRenameLatencyUITimings? = nil,
            rowValueAfter: String? = nil,
            rootValueAfter: String? = nil,
            rawAccessibilityTree: String? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let report = ClientRenameLatencyUIReport(
                status: status,
                reason: reason,
                startedAt: startedAt,
                finishedAt: codexDockISO8601Now(),
                hosts: config.hosts,
                hostID: config.hostID,
                threadID: config.threadID,
                originalTitle: config.originalTitle,
                newTitle: config.newTitle,
                serverAckDelayMS: config.serverAckDelayMS,
                uiBudgetMS: config.uiBudgetMS,
                timings: timings,
                rowValueAfter: rowValueAfter,
                rootValueAfter: rootValueAfter,
                rawAccessibilityTree: rawAccessibilityTree
            )
            try report.write(to: config.uiResultPath)
            for mirrorPath in ClientRenameLatencyProofConfig.uiResultMirrorPaths(primaryPath: config.uiResultPath) {
                try? report.write(to: mirrorPath)
            }
            guard status == .pass else {
                XCTFail(reason ?? "Client rename latency proof failed.", file: file, line: line)
                return
            }
        }

        guard app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20) else {
            try writeResult(
                status: .blocked,
                reason: "Dock search field did not appear.",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        let root = app.element(id: AutomationID.Dock.root)
        guard root.waitForDisplayedUIStringValue(containing: "loaded;", timeout: 30) else {
            try writeResult(
                status: .blocked,
                reason: "Dock did not reach loaded state before client rename latency proof.",
                rootValueAfter: root.exists ? root.displayedUIStringValue : "not-visible",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        app.collapsePinnedSectionIfExpandedForRenameProof()
        _ = app.setDockSearchText("", timeout: 5)

        guard let originalRow = app.findDockRowByIdentifierForRenameProof(
            config: config,
            title: config.originalTitle,
            timeout: 20
        ) else {
            try writeResult(
                status: .fail,
                reason: "Controlled Dock row was not visible with the original title.",
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        guard app.openRenameSheetForLatencyProof(row: originalRow, config: config) else {
            try writeResult(
                status: .fail,
                reason: "Rename action did not open for the controlled Dock row.",
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        guard let timings = app.submitRenameSheetForLatencyProof(config: config, newTitle: config.newTitle) else {
            try writeResult(
                status: .fail,
                reason: "Rename editor could not submit the controlled title.",
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        guard timings.optimisticTitleObservedAtMs != nil else {
            try writeResult(
                status: .fail,
                reason: "Optimistic Dock row title did not appear after Save.",
                timings: timings,
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        let renamedRow = app.findDockRowByIdentifierForRenameProof(
            config: config,
            title: config.newTitle,
            timeout: 1
        )

        if timings.sheetDismissMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Rename editor dismissed in \(timings.sheetDismissMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                rowValueAfter: renamedRow?.displayedUIStringValue,
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        if timings.optimisticTitleMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Optimistic title appeared in \(timings.optimisticTitleMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                rowValueAfter: renamedRow?.displayedUIStringValue,
                rootValueAfter: root.displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        try writeResult(
            status: .pass,
            reason: nil,
            timings: timings,
            rowValueAfter: renamedRow?.displayedUIStringValue,
            rootValueAfter: root.displayedUIStringValue
        )
    }

    private func launchRelayBackedApp(hosts: String? = nil) -> XCUIApplication {
        launchRelayBackedCodexDockApp(hosts: hosts)
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

private struct ClientRenameLatencyProofConfig: Decodable {
    let hosts: String
    let hostID: String
    let threadID: String
    let originalTitle: String
    let newTitle: String
    let uiResultPath: String
    let serverAckDelayMS: Int
    let uiBudgetMS: Int

    static let defaultReadyPath = "/tmp/codex-client/codex-dock-client-rename-proof-ready.json"
    static let defaultUIResultPath = "/tmp/codex-client/codex-dock-client-rename-latency-ui.json"

    static func loadFromEnvironment() throws -> ClientRenameLatencyProofConfig {
        let environment = ProcessInfo.processInfo.environment
        let readyPath = nonEmpty(environment["CODEX_DOCK_CLIENT_RENAME_PROOF_READY"])
            ?? defaultReadyPath
        guard FileManager.default.fileExists(atPath: readyPath) else {
            throw XCTSkip("Controlled client rename latency ready file does not exist at \(readyPath).")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: readyPath))
        return try JSONDecoder().decode(ClientRenameLatencyProofConfig.self, from: data)
    }

    static func uiResultMirrorPaths(primaryPath: String) -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let paths = [
            nonEmpty(environment["CODEX_DOCK_CLIENT_RENAME_PROOF_UI_RESULT_HOST"]),
            defaultUIResultPath
        ].compactMap(\.self)
        var seen = Set([primaryPath])
        return paths.filter { seen.insert($0).inserted }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct ClientRenameLatencyUITimings: Codable {
    var saveTappedAt: String
    var saveTappedAtMs: Int64
    var sheetDismissedAt: String
    var sheetDismissedAtMs: Int64
    var sheetDismissMS: Int
    var optimisticTitleObservedAt: String?
    var optimisticTitleObservedAtMs: Int64?
    var optimisticTitleMS: Int
}

private struct ClientRenameLatencyUIReport: Codable {
    var schemaVersion = 1
    var kind = "codex-dock-client-rename-latency-ui-proof"
    var status: DisplayedUIArtifactStatus
    var reason: String?
    var startedAt: String
    var finishedAt: String
    var hosts: String
    var hostID: String
    var threadID: String
    var originalTitle: String
    var newTitle: String
    var serverAckDelayMS: Int
    var uiBudgetMS: Int
    var timings: ClientRenameLatencyUITimings?
    var rowValueAfter: String?
    var rootValueAfter: String?
    var rawAccessibilityTree: String?

    func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

private func codexDockNowMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
}

private func codexDockISO8601String(fromMilliseconds milliseconds: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
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

    func findDockRowByIdentifierForRenameProof(
        config: ClientRenameLatencyProofConfig,
        title: String,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let identifier = AutomationID.Dock.row(hostID: config.hostID, threadID: config.threadID).rawValue
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = largestVisibleElement(exactIdentifier: identifier),
               row.label.localizedCaseInsensitiveContains(title) {
                return row
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    func openRenameSheetForLatencyProof(
        row: XCUIElement,
        config: ClientRenameLatencyProofConfig
    ) -> Bool {
        row.press(forDuration: 0.8)

        let actionID = AutomationID.Dock.rowAction(
            hostID: config.hostID,
            threadID: config.threadID,
            action: .rename
        )
        let renameAction = element(id: actionID)
        if renameAction.waitForExistence(timeout: 2) {
            renameAction.tap()
            return element(id: AutomationID.Dock.renameSheet).waitForExistence(timeout: 5)
        }

        let fallback = buttons["Rename"].firstMatch
        guard fallback.waitForExistence(timeout: 2) else {
            return false
        }
        fallback.tap()
        return element(id: AutomationID.Dock.renameSheet).waitForExistence(timeout: 5)
    }

    func submitRenameSheetForLatencyProof(
        config: ClientRenameLatencyProofConfig,
        newTitle: String
    ) -> ClientRenameLatencyUITimings? {
        let sheet = element(id: AutomationID.Dock.renameSheet)
        guard sheet.waitForExistence(timeout: 5) else {
            return nil
        }

        let field = textFields.matching(identifier: AutomationID.Dock.renameNameField.rawValue).firstMatch
        guard field.waitForExistence(timeout: 5) else {
            return nil
        }
        guard replaceRenameFieldTextForLatencyProof(field, with: newTitle) else {
            return nil
        }

        let saveButton = buttons.matching(identifier: AutomationID.Dock.renameSaveButton.rawValue).firstMatch
        guard waitForEnabledElement(saveButton, timeout: 5) else {
            return nil
        }

        let saveTappedAtMs = codexDockNowMilliseconds()
        saveButton.tap()
        let observations = waitForRenameLatencyObservations(
            config: config,
            title: newTitle,
            editorControl: saveButton,
            timeout: max(3, Double(config.uiBudgetMS) / 1_000 + 2)
        )
        let sheetDismissedAtMs = observations.sheetDismissedAtMs ?? -1
        let optimisticTitleObservedAtMs = observations.optimisticTitleObservedAtMs

        return ClientRenameLatencyUITimings(
            saveTappedAt: codexDockISO8601String(fromMilliseconds: saveTappedAtMs),
            saveTappedAtMs: saveTappedAtMs,
            sheetDismissedAt: observations.sheetDismissedAtMs.map { codexDockISO8601String(fromMilliseconds: $0) } ?? "not-observed",
            sheetDismissedAtMs: sheetDismissedAtMs,
            sheetDismissMS: observations.sheetDismissedAtMs.map { Int($0 - saveTappedAtMs) } ?? Int.max,
            optimisticTitleObservedAt: optimisticTitleObservedAtMs.map { codexDockISO8601String(fromMilliseconds: $0) },
            optimisticTitleObservedAtMs: optimisticTitleObservedAtMs,
            optimisticTitleMS: optimisticTitleObservedAtMs.map { Int($0 - saveTappedAtMs) } ?? Int.max
        )
    }

    func replaceRenameFieldTextForLatencyProof(_ field: XCUIElement, with text: String) -> Bool {
        for _ in 0..<3 {
            let currentValue = field.value as? String
            let deleteCount = max((currentValue?.count ?? 0) + 2, text.count + 2)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(deleteCount, 80)))
            field.typeText(text)
            if (field.value as? String) == text {
                return true
            }
        }
        return (field.value as? String) == text
    }

    func waitForRenameLatencyObservations(
        config: ClientRenameLatencyProofConfig,
        title: String,
        editorControl: XCUIElement,
        timeout: TimeInterval
    ) -> (sheetDismissedAtMs: Int64?, optimisticTitleObservedAtMs: Int64?) {
        let identifier = AutomationID.Dock.row(hostID: config.hostID, threadID: config.threadID).rawValue
        let deadline = Date().addingTimeInterval(timeout)
        var sheetDismissedAtMs: Int64?
        var optimisticTitleObservedAtMs: Int64?
        while Date() < deadline {
            if sheetDismissedAtMs == nil, !editorControl.exists || !editorControl.isHittable {
                sheetDismissedAtMs = codexDockNowMilliseconds()
            }
            if optimisticTitleObservedAtMs == nil,
               let row = largestVisibleElement(exactIdentifier: identifier),
               row.label.localizedCaseInsensitiveContains(title) {
                optimisticTitleObservedAtMs = codexDockNowMilliseconds()
            }
            if sheetDismissedAtMs != nil, optimisticTitleObservedAtMs != nil {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if sheetDismissedAtMs == nil, !editorControl.exists || !editorControl.isHittable {
            sheetDismissedAtMs = codexDockNowMilliseconds()
        }
        if optimisticTitleObservedAtMs == nil,
           let row = largestVisibleElement(exactIdentifier: identifier),
           row.label.localizedCaseInsensitiveContains(title) {
            optimisticTitleObservedAtMs = codexDockNowMilliseconds()
        }
        return (sheetDismissedAtMs, optimisticTitleObservedAtMs)
    }

    func waitForElementToDisappearTimestamp(
        id: AutomationID,
        timeout: TimeInterval
    ) -> Int64? {
        let element = element(id: id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return codexDockNowMilliseconds()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return !element.exists ? codexDockNowMilliseconds() : nil
    }

    func waitForDockRowTitleTimestampForRenameProof(
        config: ClientRenameLatencyProofConfig,
        title: String,
        timeout: TimeInterval
    ) -> Int64? {
        let identifier = AutomationID.Dock.row(hostID: config.hostID, threadID: config.threadID).rawValue
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = largestVisibleElement(exactIdentifier: identifier),
               row.label.localizedCaseInsensitiveContains(title) {
                return codexDockNowMilliseconds()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
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
