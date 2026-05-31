import CodexDock
import XCTest

@MainActor
final class CodexDockDisplayedSyncProofTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSamplesRelayBackedDockDisplayOverTime() throws {
        let config = try DisplayedUISyncConfig.load()
        let app = launchRelayBackedApp(hosts: config.hosts)

        let startIdentifier = app.waitForFirstIdentifier([
            AutomationID.Dock.root.rawValue,
            AutomationID.Bootstrap.manualHostField.rawValue,
        ], timeout: 30)
        XCTAssertEqual(
            startIdentifier,
            AutomationID.Dock.root.rawValue,
            "Displayed sync proof must start on the relay-backed Dock UI, not the bootstrap form.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        let root = app.element(id: AutomationID.Dock.root.rawValue)
        XCTAssertTrue(
            root.waitForStringValue(matching: { value in
                value.contains("loaded") && !value.contains("Partial")
            }, timeout: 30),
            "Dock did not reach complete loaded state before sampling. Root value: \(root.stringValue)"
        )

        var samples: [DisplayedUISample] = []
        var sampleIndex = 0

        if let openThreadID = config.openThreadID {
            samples.append(app.captureDisplayedUISample(index: sampleIndex))
            sampleIndex += 1
            RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(config.sampleMS) / 1000.0))
            samples.append(app.captureDisplayedUISample(index: sampleIndex))
            sampleIndex += 1

            guard let row = app.visibleDockRow(hostID: config.openHostID, threadID: openThreadID, timeout: 15) else {
                XCTFail("Displayed sync proof could not find target Dock row host=\(config.openHostID ?? "*") thread=\(openThreadID).\n\nAccessibility tree:\n\(app.debugDescription)")
                return
            }
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertNotNil(
                app.waitForElement(identifierPrefix: AutomationID.Session.root(threadID: openThreadID).rawValue, timeout: 15),
                "Displayed sync proof did not reach target thread detail for \(openThreadID)."
            )
            if let detailFilter = config.detailFilter {
                XCTAssertTrue(
                    app.selectMessageFilter(detailFilter, timeout: 10),
                    "Displayed sync proof could not switch the real detail filter to \(detailFilter)."
                )
            }

            try DisplayedUISampleWriter.markReady(to: config.readyPath)

            let deadline = Date().addingTimeInterval(TimeInterval(config.durationMS) / 1000.0)
            var didTapRequestAction = false
            repeat {
                let sample = app.captureDisplayedUISample(index: sampleIndex)
                samples.append(sample)
                sampleIndex += 1
                if !didTapRequestAction,
                   let cardID = config.requestCardID,
                   let action = config.requestAction,
                   sample.detail?.containsRequestCard(cardID: cardID) == true,
                   app.tapRequestAction(cardID: cardID, action: action, timeout: 0.2) {
                    didTapRequestAction = true
                }
                RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(config.sampleMS) / 1000.0))
            } while Date() < deadline

            if config.detailCheckpointSweep == true {
                samples.append(app.captureDisplayedUISample(index: sampleIndex, includeDetailSweep: true))
                sampleIndex += 1
            }
        } else {
            try DisplayedUISampleWriter.markReady(to: config.readyPath)

            let deadline = Date().addingTimeInterval(TimeInterval(config.durationMS) / 1000.0)
            repeat {
                samples.append(app.captureDisplayedUISample(index: sampleIndex))
                sampleIndex += 1
                RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(config.sampleMS) / 1000.0))
            } while Date() < deadline

            if config.checkpointSweep == true {
                samples.append(app.captureDisplayedUISample(index: sampleIndex, includeDockSweep: true))
                sampleIndex += 1
            }

            if let row = app.firstVisibleDockRow(timeout: 5) {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                if app.waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 15) != nil {
                    samples.append(app.captureDisplayedUISample(index: sampleIndex))
                }
            }
        }

        if config.openThreadID != nil, config.checkpointSweep == true {
            if let backButton = app.navigationBars.buttons.firstMatchIfExists {
                backButton.tap()
                if root.waitForStringValue(matching: { value in
                    value.contains("loaded") && !value.contains("Partial")
                }, timeout: 10) {
                    samples.append(app.captureDisplayedUISample(index: sampleIndex, includeDockSweep: true))
                    sampleIndex += 1
                }
            } else if elementExists(app.element(id: AutomationID.Dock.root.rawValue)) {
                samples.append(app.captureDisplayedUISample(index: sampleIndex))
                sampleIndex += 1
            }
        }

        XCTAssertFalse(samples.isEmpty, "Displayed sync proof did not record any UI samples.")
        XCTAssertTrue(
            samples.contains(where: { $0.dockRootValue.contains("loaded") }),
            "Displayed sync proof never observed the Dock loaded state."
        )

        try DisplayedUISampleWriter.write(samples, to: config.outputPath)
        add(XCTAttachment(string: samples.map(\.jsonLine).joined(separator: "\n")))
    }

    private func launchRelayBackedApp(hosts: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
        app.launchEnvironment.removeValue(forKey: "CODEX_DOCK_UI_DOCK_STREAM_SCENARIO")
        app.terminate()
        app.launch()
        return app
    }
}

private struct DisplayedUISyncConfig: Codable {
    var outputPath: String
    var hosts: String
    var durationMS: Int
    var sampleMS: Int
    var expiresAt: String
    var readyPath: String?
    var checkpointSweep: Bool?
    var detailCheckpointSweep: Bool?
    var openHostID: String?
    var openThreadID: String?
    var requestCardID: String?
    var requestAction: String?
    var detailFilter: String?

    static let path = "/tmp/codex-client/codex-dock-sim-ui-sync-config.json"

    static func load() throws -> DisplayedUISyncConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Create \(path) to run the real simulator displayed-UI sync proof.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try JSONDecoder().decode(DisplayedUISyncConfig.self, from: data)
        guard let expiry = ISO8601DateFormatter().date(from: config.expiresAt), expiry > Date() else {
            throw XCTSkip("Simulator displayed-UI sync proof config at \(path) is expired.")
        }
        return config
    }
}

private struct DisplayedUISample: Codable {
    var sampleIndex: Int
    var sampledAt: String
    var finishedAt: String
    var dockRootValue: String
    var dockRows: [DisplayedUIDockRow]
    var hostSummaries: [DisplayedUIElementSnapshot]
    var dockSweep: DisplayedUIDockSweep?
    var detail: DisplayedUIDetail?
    var detailSweep: DisplayedUIDetailSweep?

    var jsonLine: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let line = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return line
    }
}

private struct DisplayedUIDockRow: Codable {
    var identifier: String
    var value: String
    var label: String
    var frame: DisplayedUIFrame
}

private struct DisplayedUIDockSweep: Codable {
    var startedAt: String
    var finishedAt: String
    var stepCount: Int
    var expectedRootRows: Int?
    var rows: [DisplayedUIDockRow]
}

private struct DisplayedUIDetail: Codable {
    var startedAt: String
    var finishedAt: String
    var rootIdentifier: String
    var rootCapturedAt: String
    var rootValue: String
    var headerCapturedAt: String
    var headerValue: String
    var messageListCapturedAt: String
    var messageListValue: String
    var messageCardsCapturedAt: String
    var messageCardIDs: [String]
    var requestElementsCapturedAt: String
    var requestCardIDs: [String]
    var messageCards: [DisplayedUIElementSnapshot]
    var requestElements: [DisplayedUIElementSnapshot]

    func containsRequestCard(cardID: String) -> Bool {
        let identifier = AutomationID.RequestCard.card(cardID: cardID).rawValue
        return requestCardIDs.contains(identifier)
            || requestElements.contains(where: { $0.identifier == identifier })
    }
}

private struct DisplayedUIDetailSweep: Codable {
    var startedAt: String
    var finishedAt: String
    var stepCount: Int
    var expectedMessageRows: Int?
    var messageCardIDs: [String]
    var requestCardIDs: [String]
    var messageCards: [DisplayedUIElementSnapshot]
    var requestElements: [DisplayedUIElementSnapshot]
}

private struct DisplayedUIElementSnapshot: Codable {
    var identifier: String
    var capturedAt: String
    var value: String
    var label: String
}

private struct DisplayedUIFrame: Codable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    init(_ frame: CGRect) {
        minX = frame.minX
        minY = frame.minY
        width = frame.width
        height = frame.height
    }
}

private enum DisplayedUISampleWriter {
    static func write(_ samples: [DisplayedUISample], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let body = samples.map(\.jsonLine).joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    static func markReady(to path: String?) throws {
        guard let path else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let body = #"{"ready":true}"# + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
private extension XCUIApplication {
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

    func waitForElement(identifierPrefix: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
            let element = descendants(matching: .any).matching(predicate).firstMatch
            if element.exists {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func firstVisibleDockRow(timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "codexdock.dock.row.")
        while Date() < deadline {
            let rows = buttons.matching(predicate).allElementsBoundByIndex
            for row in rows.prefix(50) {
                guard !row.identifier.contains(".action.") else {
                    continue
                }
                guard isVisibleForTap(row.frame) else {
                    continue
                }
                return row
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func visibleDockRow(hostID: String?, threadID: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hostID {
                let exact = element(id: AutomationID.Dock.row(hostID: hostID, threadID: threadID).rawValue)
                if exact.exists, isVisibleForTap(exact.frame) {
                    return exact
                }
            }

            let rows = visibleDockRows()
            if let row = rows.first(where: { candidate in
                candidate.value.contains("thread=\(threadID);") || candidate.value.contains("thread=\(threadID)")
            }) {
                let element = element(id: row.identifier)
                if element.exists, isVisibleForTap(element.frame) {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func tapRequestAction(cardID: String, action: String, timeout: TimeInterval) -> Bool {
        let identifier: String
        switch action {
        case "approve":
            identifier = AutomationID.RequestCard.approveButton(cardID: cardID).rawValue
        case "decline":
            identifier = AutomationID.RequestCard.declineButton(cardID: cardID).rawValue
        case "send":
            identifier = AutomationID.RequestCard.sendButton(cardID: cardID).rawValue
        default:
            return false
        }

        let button = element(id: identifier)
        guard button.waitForExistence(timeout: timeout), button.isEnabled, isVisibleForTap(button.frame) else {
            return false
        }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    func selectMessageFilter(_ filter: String, timeout: TimeInterval) -> Bool {
        let expectedValue = filter
        let control = element(id: AutomationID.Session.messageFilter.rawValue)
        guard control.waitForExistence(timeout: timeout) else {
            return false
        }
        if control.stringValue == expectedValue {
            return true
        }
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let label: String
        switch filter {
        case "all":
            label = "All"
        case "messages":
            label = "Messages"
        case "request":
            label = "Requests"
        default:
            label = filter
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let option = buttons[label].firstMatch
            if option.exists {
                option.tap()
                return control.waitForStringValue(matching: { $0 == expectedValue }, timeout: timeout)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func captureDisplayedUISample(
        index: Int,
        includeDockSweep: Bool = false,
        includeDetailSweep: Bool = false
    ) -> DisplayedUISample {
        let sampledAt = codexDockISO8601Now()
        let dockRoot = element(id: AutomationID.Dock.root.rawValue)
        let rootValue = dockRoot.exists ? dockRoot.stringValue : "not-visible"
        let dockRows = visibleDockRows()
        let dockSweep = includeDockSweep ? checkpointDockSweep(rootValue: rootValue) : nil
        let detail = visibleDetail()
        let detailSweep = includeDetailSweep ? checkpointDetailSweep() : nil
        return DisplayedUISample(
            sampleIndex: index,
            sampledAt: sampledAt,
            finishedAt: codexDockISO8601Now(),
            dockRootValue: rootValue,
            dockRows: dockRows,
            hostSummaries: hostSummarySnapshots(),
            dockSweep: dockSweep,
            detail: detail,
            detailSweep: detailSweep
        )
    }

    private func checkpointDockSweep(rootValue: String) -> DisplayedUIDockSweep {
        let startedAt = codexDockISO8601Now()
        let expectedRootRows = dockRootRowCount(rootValue)
        var rows: [DisplayedUIDockRow] = []
        var seen = Set<String>()
        var lastVisibleIdentifier: String?
        var stableTailCount = 0
        var stepCount = 0

        for _ in 0..<30 {
            stepCount += 1
            let visibleRows = visibleDockRows()
            for row in visibleRows where seen.insert(row.identifier).inserted {
                rows.append(row)
            }
            if let expectedRootRows, rows.count >= expectedRootRows {
                break
            }

            let currentLast = visibleRows.last?.identifier
            if currentLast == nil {
                break
            }
            if currentLast == lastVisibleIdentifier {
                stableTailCount += 1
                if stableTailCount >= 2 {
                    break
                }
            } else {
                stableTailCount = 0
            }
            lastVisibleIdentifier = currentLast
            dragDockListUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return DisplayedUIDockSweep(
            startedAt: startedAt,
            finishedAt: codexDockISO8601Now(),
            stepCount: stepCount,
            expectedRootRows: expectedRootRows,
            rows: rows
        )
    }

    private func dragDockListUp() {
        let window = windows.firstMatch
        guard window.exists else {
            swipeUp()
            return
        }
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func dockRootRowCount(_ rootValue: String) -> Int? {
        for part in rootValue.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("rows=") else {
                continue
            }
            return Int(trimmed.dropFirst("rows=".count))
        }
        return nil
    }

    private func checkpointDetailSweep() -> DisplayedUIDetailSweep {
        let startedAt = codexDockISO8601Now()
        var messageCardIDs: [String] = []
        var requestCardIDs: [String] = []
        var messageCards: [DisplayedUIElementSnapshot] = []
        var requestElements: [DisplayedUIElementSnapshot] = []
        var seenMessageCardIDs = Set<String>()
        var seenRequestCardIDs = Set<String>()
        var seenMessageSnapshots = Set<String>()
        var seenRequestSnapshots = Set<String>()
        var expectedMessageRows: Int?
        var lastVisibleIdentifier: String?
        var stableTailCount = 0
        var stepCount = 0

        func appendUnique(_ source: [String], to target: inout [String], seen: inout Set<String>) {
            for value in source where seen.insert(value).inserted {
                target.append(value)
            }
        }

        func appendUniqueSnapshots(
            _ source: [DisplayedUIElementSnapshot],
            to target: inout [DisplayedUIElementSnapshot],
            seen: inout Set<String>
        ) {
            for value in source where seen.insert(value.identifier).inserted {
                target.append(value)
            }
        }

        for _ in 0..<30 {
            stepCount += 1
            guard let detail = visibleDetail() else {
                break
            }
            if expectedMessageRows == nil {
                expectedMessageRows = detailMessageCount(detail.messageListValue)
            }
            appendUnique(detail.messageCardIDs, to: &messageCardIDs, seen: &seenMessageCardIDs)
            appendUnique(detail.requestCardIDs, to: &requestCardIDs, seen: &seenRequestCardIDs)
            appendUniqueSnapshots(detail.messageCards, to: &messageCards, seen: &seenMessageSnapshots)
            appendUniqueSnapshots(detail.requestElements, to: &requestElements, seen: &seenRequestSnapshots)

            if let expectedMessageRows, messageCardIDs.count >= expectedMessageRows {
                break
            }

            let currentLast = (detail.messageCardIDs + detail.requestCardIDs).last
            if currentLast == nil {
                break
            }
            if currentLast == lastVisibleIdentifier {
                stableTailCount += 1
                if stableTailCount >= 2 {
                    break
                }
            } else {
                stableTailCount = 0
            }
            lastVisibleIdentifier = currentLast
            dragDockListUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return DisplayedUIDetailSweep(
            startedAt: startedAt,
            finishedAt: codexDockISO8601Now(),
            stepCount: stepCount,
            expectedMessageRows: expectedMessageRows,
            messageCardIDs: messageCardIDs,
            requestCardIDs: requestCardIDs,
            messageCards: messageCards,
            requestElements: requestElements
        )
    }

    private func detailMessageCount(_ messageListValue: String) -> Int? {
        for part in messageListValue.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("events=") else {
                continue
            }
            return Int(trimmed.dropFirst("events=".count))
        }
        return nil
    }

    private func visibleDockRows() -> [DisplayedUIDockRow] {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "codexdock.dock.row.")
        var rows: [DisplayedUIDockRow] = []
        let candidates = buttons.matching(predicate).allElementsBoundByIndex
        for row in candidates.prefix(80) {
            guard !row.identifier.contains(".action.") else {
                continue
            }
            guard isVisibleForTap(row.frame) else {
                continue
            }
            rows.append(
                DisplayedUIDockRow(
                    identifier: row.identifier,
                    value: row.stringValue,
                    label: row.label,
                    frame: DisplayedUIFrame(row.frame)
                )
            )
        }
        return rows
    }

    private func hostSummarySnapshots() -> [DisplayedUIElementSnapshot] {
        elementSnapshots(prefix: "codexdock.dock.host.")
            .filter { snapshot in
                !snapshot.identifier.hasSuffix(".retry")
                    && !snapshot.identifier.hasSuffix(".relay-settings")
            }
    }

    private func visibleDetail() -> DisplayedUIDetail? {
        let startedAt = codexDockISO8601Now()
        let root = waitForElement(identifierPrefix: "codexdock.session.root.", timeout: 0.1)
        guard let root, root.exists else {
            return nil
        }
        let rootValue = root.stringValue
        let rootCapturedAt = codexDockISO8601Now()
        let messageCards = elementSnapshots(prefix: "codexdock.session.message.")
        let messageCardsCapturedAt = codexDockISO8601Now()
        let requestElements = elementSnapshots(prefix: "codexdock.session.request.")
        let requestElementsCapturedAt = codexDockISO8601Now()
        let headerValue = optionalStringValue(id: AutomationID.Session.header.rawValue)
        let headerCapturedAt = codexDockISO8601Now()
        let messageListValue = optionalStringValue(id: AutomationID.Session.messageList.rawValue)
        let messageListCapturedAt = codexDockISO8601Now()
        return DisplayedUIDetail(
            startedAt: startedAt,
            finishedAt: codexDockISO8601Now(),
            rootIdentifier: root.identifier,
            rootCapturedAt: rootCapturedAt,
            rootValue: rootValue,
            headerCapturedAt: headerCapturedAt,
            headerValue: headerValue,
            messageListCapturedAt: messageListCapturedAt,
            messageListValue: messageListValue,
            messageCardsCapturedAt: messageCardsCapturedAt,
            messageCardIDs: messageCards.map(\.identifier).sorted(),
            requestElementsCapturedAt: requestElementsCapturedAt,
            requestCardIDs: requestElements.map(\.identifier).sorted(),
            messageCards: messageCards,
            requestElements: requestElements
        )
    }

    private func optionalStringValue(id: String) -> String {
        let target = element(id: id)
        return target.exists ? target.stringValue : "not-visible"
    }

    private func elementSnapshots(prefix: String) -> [DisplayedUIElementSnapshot] {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        let elements = descendants(matching: .any).matching(predicate).allElementsBoundByIndex
        var snapshots: [DisplayedUIElementSnapshot] = []
        var seen = Set<String>()
        for element in elements.prefix(120) {
            let identifier = element.identifier
            guard seen.insert(identifier).inserted else {
                continue
            }
            let value = element.stringValue
            let label = element.label
            snapshots.append(
                DisplayedUIElementSnapshot(
                    identifier: identifier,
                    capturedAt: codexDockISO8601Now(),
                    value: value,
                    label: label
                )
            )
        }
        return snapshots.sorted { left, right in
            left.identifier < right.identifier
        }
    }

    private func isVisibleForTap(_ frame: CGRect) -> Bool {
        guard frame.width > 1, frame.height > 1 else {
            return false
        }
        let window = windows.firstMatch
        let visibleFrame = window.exists ? window.frame : frame
        let bottomLimit = tabBars.firstMatch.exists
            ? tabBars.firstMatch.frame.minY - 1
            : visibleFrame.maxY - 1
        return frame.midY >= visibleFrame.minY + 1
            && frame.midY <= bottomLimit
            && frame.maxX > visibleFrame.minX
            && frame.minX < visibleFrame.maxX
    }
}

@MainActor
private func elementExists(_ element: XCUIElement) -> Bool {
    element.exists
}

private extension XCUIElementQuery {
    var firstMatchIfExists: XCUIElement? {
        let candidate = firstMatch
        return candidate.exists ? candidate : nil
    }
}

private func codexDockISO8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private extension XCUIElement {
    var stringValue: String {
        if let value = self.value as? String {
            return value
        }
        return label
    }

    func waitForStringValue(containing expected: String, timeout: TimeInterval) -> Bool {
        waitForStringValue(matching: { $0.contains(expected) }, timeout: timeout)
    }

    func waitForStringValue(matching predicate: (String) -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(stringValue) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
