import CodexDock
import XCTest

enum DisplayedUIArtifactStatus: String, Codable {
    case pass
    case fail
    case blocked
    case notRun = "not_run"
}

enum DisplayedUIScreenKind: String, Codable {
    case dock
    case thread
    case archive
    case unknown
}

struct DisplayedUISample: Codable {
    var sampleIndex: Int
    var sampledAt: String
    var finishedAt: String
    var dockRootValue: String
    var dockRowsCapturedAt: String
    var dockRows: [DisplayedUIDockRow]
    var hostSummaries: [DisplayedUIElementSnapshot]
    var dockSweep: DisplayedUIDockSweep?
    var detail: DisplayedUIDetail?
    var detailSweep: DisplayedUIDetailSweep?

    var screenKind: DisplayedUIScreenKind {
        if detail != nil {
            return .thread
        }
        if dockRootValue != "not-visible" || !dockRows.isEmpty {
            return .dock
        }
        return .unknown
    }

    var activeThreadID: String? {
        detail?.threadID
    }

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

struct DisplayedUIDockRow: Codable {
    var identifier: String
    var value: String
    var label: String
    var frame: DisplayedUIFrame
}

struct DisplayedUIDockSweep: Codable {
    var startedAt: String
    var finishedAt: String
    var stepCount: Int
    var maxSteps: Int
    var stopReason: String
    var expectedRootRows: Int?
    var rows: [DisplayedUIDockRow]
}

struct DisplayedUIDetail: Codable {
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

    var threadID: String? {
        codexDockAutomationField("thread", in: rootValue)
            ?? codexDockAutomationField("thread", in: headerValue)
    }

    func containsRequestCard(cardID: String) -> Bool {
        let identifier = AutomationID.RequestCard.card(cardID: cardID).rawValue
        return requestCardIDs.contains(identifier)
            || requestElements.contains(where: { $0.identifier == identifier })
    }
}

struct DisplayedUIDetailSweep: Codable {
    var startedAt: String
    var finishedAt: String
    var stepCount: Int
    var expectedMessageRows: Int?
    var messageCardIDs: [String]
    var requestCardIDs: [String]
    var messageCards: [DisplayedUIElementSnapshot]
    var requestElements: [DisplayedUIElementSnapshot]
}

struct DisplayedUIElementSnapshot: Codable {
    var identifier: String
    var capturedAt: String
    var value: String
    var label: String
    var frame: DisplayedUIFrame
}

struct DisplayedUIVisibleElementSnapshot: Codable {
    var identifier: String
    var elementType: String
    var label: String
    var value: String
    var frame: DisplayedUIFrame
}

struct DisplayedUIFrame: Codable {
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

@MainActor
extension XCUIApplication {
    func displayedUIElement(id: String) -> XCUIElement {
        descendants(matching: .any)[id]
    }

    func displayedUIWaitForFirstIdentifier(_ identifiers: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers where displayedUIElement(id: identifier).exists {
                return identifier
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    func displayedUIWaitForElement(identifierPrefix: String, timeout: TimeInterval) -> XCUIElement? {
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
                let exact = displayedUIElement(id: AutomationID.Dock.row(hostID: hostID, threadID: threadID).rawValue)
                if exact.exists, isVisibleForTap(exact.frame) {
                    return exact
                }
            }

            let rows = visibleDockRows()
            if let row = rows.first(where: { candidate in
                candidate.value.contains("thread=\(threadID);") || candidate.value.contains("thread=\(threadID)")
            }) {
                let element = displayedUIElement(id: row.identifier)
                if element.exists, isVisibleForTap(element.frame) {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    func setDockSearchText(_ text: String, timeout: TimeInterval) -> Bool {
        let field = displayedUIElement(id: AutomationID.Dock.searchField.rawValue)
        guard field.waitForExistence(timeout: timeout) else {
            return false
        }

        let clearButton = displayedUIElement(id: AutomationID.Dock.clearSearchButton.rawValue)
        if clearButton.exists, isVisibleForTap(clearButton.frame) {
            clearButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        field.typeText(text)
        return field.waitForDisplayedUIStringValue(matching: { value in
            value.localizedCaseInsensitiveContains(text)
        }, timeout: timeout)
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

        let button = displayedUIElement(id: identifier)
        guard button.waitForExistence(timeout: timeout), button.isEnabled, isVisibleForTap(button.frame) else {
            return false
        }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    func tapRequestAction(requestCardIdentifier: String, action: String, timeout: TimeInterval) -> Bool {
        let suffix: String
        switch action {
        case "approve":
            suffix = ".approve"
        case "decline":
            suffix = ".decline"
        case "send":
            suffix = ".send"
        default:
            return false
        }

        let button = displayedUIElement(id: "\(requestCardIdentifier)\(suffix)")
        guard button.waitForExistence(timeout: timeout), button.isEnabled, isVisibleForTap(button.frame) else {
            return false
        }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    func selectMessageFilter(_ filter: String, timeout: TimeInterval) -> Bool {
        let expectedValue = filter
        let control = displayedUIElement(id: AutomationID.Session.messageFilter.rawValue)
        guard control.waitForExistence(timeout: timeout) else {
            return false
        }
        if control.displayedUIStringValue == expectedValue {
            return true
        }
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let labels: [String]
        switch filter {
        case "all":
            labels = ["All"]
        case "messages":
            labels = ["Messages"]
        case "userMessage":
            labels = ["User"]
        case "agentMessage":
            labels = ["Agent"]
        case "command":
            labels = ["Command"]
        case "output":
            labels = ["Output"]
        case "request":
            labels = ["Request", "Requests"]
        case "system":
            labels = ["System"]
        case "unknown":
            labels = ["Unknown"]
        default:
            labels = [filter]
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let option = buttons[label].firstMatch
                if option.exists {
                    option.tap()
                    return control.waitForDisplayedUIStringValue(matching: { $0 == expectedValue }, timeout: timeout)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func scrollDetailMessagesIntoEvidencePosition(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let detail = visibleDetail() {
                let expectedMessageRows = detailMessageCount(detail.messageListValue)
                if expectedMessageRows == 0 || !detail.messageCardIDs.isEmpty {
                    return true
                }
            }
            dragDetailPageUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        guard let detail = visibleDetail() else {
            return false
        }
        let expectedMessageRows = detailMessageCount(detail.messageListValue)
        return expectedMessageRows == 0 || !detail.messageCardIDs.isEmpty
    }

    func captureDisplayedUISample(
        index: Int,
        includeDockSweep: Bool = false,
        includeDetailSweep: Bool = false
    ) -> DisplayedUISample {
        let sampledAt = codexDockISO8601Now()
        let dockRoot = displayedUIElement(id: AutomationID.Dock.root.rawValue)
        let rootValue = dockRoot.exists ? dockRoot.displayedUIStringValue : "not-visible"
        let dockRows = visibleDockRows()
        let dockRowsCapturedAt = codexDockISO8601Now()
        let dockSweep = includeDockSweep ? checkpointDockSweep(rootValue: rootValue) : nil
        let detail = visibleDetail()
        let detailSweep = includeDetailSweep ? checkpointDetailSweep() : nil
        // Dock host summaries are Dock-screen evidence only. Querying them from
        // Thread Detail forces a broad accessibility scan and can drop the UI
        // test connection before the real detail sample is written.
        let hostSummaries = detail == nil ? hostSummarySnapshots() : []
        return DisplayedUISample(
            sampleIndex: index,
            sampledAt: sampledAt,
            finishedAt: codexDockISO8601Now(),
            dockRootValue: rootValue,
            dockRowsCapturedAt: dockRowsCapturedAt,
            dockRows: dockRows,
            hostSummaries: hostSummaries,
            dockSweep: dockSweep,
            detail: detail,
            detailSweep: detailSweep
        )
    }

    func visibleScreenKind(from sample: DisplayedUISample) -> DisplayedUIScreenKind {
        if sample.detail != nil {
            return .thread
        }
        if displayedUIElement(id: AutomationID.Dock.root.rawValue).exists || !sample.dockRows.isEmpty {
            return .dock
        }
        if displayedUIElement(id: AutomationID.Archive.root.rawValue).exists {
            return .archive
        }
        return .unknown
    }

    func visibleAccessibilityElements(limit: Int = 300) -> [DisplayedUIVisibleElementSnapshot] {
        let elements = descendants(matching: .any).allElementsBoundByIndex
        var snapshots: [DisplayedUIVisibleElementSnapshot] = []
        var seen = Set<String>()
        for element in elements.prefix(limit * 3) {
            guard isVisibleForTap(element.frame) else {
                continue
            }
            let frame = DisplayedUIFrame(element.frame)
            let key = [
                element.identifier,
                element.label,
                element.displayedUIStringValue,
                String(format: "%.1f", frame.minX),
                String(format: "%.1f", frame.minY),
                String(format: "%.1f", frame.width),
                String(format: "%.1f", frame.height),
            ].joined(separator: "|")
            guard seen.insert(key).inserted else {
                continue
            }
            snapshots.append(
                DisplayedUIVisibleElementSnapshot(
                    identifier: element.identifier,
                    elementType: "\(element.elementType)",
                    label: element.label,
                    value: element.displayedUIStringValue,
                    frame: frame
                )
            )
            if snapshots.count >= limit {
                break
            }
        }
        return snapshots
    }

    private func checkpointDockSweep(rootValue: String) -> DisplayedUIDockSweep {
        let startedAt = codexDockISO8601Now()
        let expectedRootRows = dockRootRowCount(rootValue)
        var rows: [DisplayedUIDockRow] = []
        var seen = Set<String>()
        var lastVisibleIdentifier: String?
        var stableTailCount = 0
        var stepCount = 0
        let maxSteps = 30
        let deadline = Date().addingTimeInterval(20)
        var stopReason = "maxSteps"

        for _ in 0..<maxSteps {
            if Date() >= deadline {
                stopReason = "timeBudget"
                break
            }
            stepCount += 1
            let visibleRows = visibleDockRows()
            for row in visibleRows where seen.insert(row.identifier).inserted {
                rows.append(row)
            }
            if let expectedRootRows, rows.count >= expectedRootRows {
                stopReason = "expectedRowsReached"
                break
            }

            let currentLast = visibleRows.last?.identifier
            if currentLast == nil {
                stopReason = "noVisibleRows"
                break
            }
            if currentLast == lastVisibleIdentifier {
                stableTailCount += 1
                if stableTailCount >= 2 {
                    stopReason = "stableTail"
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
            maxSteps: maxSteps,
            stopReason: stopReason,
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

    private func dragDetailPageUp() {
        let root = displayedUIWaitForElement(identifierPrefix: "codexdock.session.root.", timeout: 0.1)
        guard let root, root.exists else {
            dragDockListUp()
            return
        }
        let start = root.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = root.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
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
        let deadline = Date().addingTimeInterval(20)

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
            if Date() >= deadline {
                break
            }
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
                if let expectedMessageRows, messageCardIDs.count < expectedMessageRows {
                    dragDetailPageUp()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                    continue
                }
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
            dragDetailPageUp()
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
                    value: row.displayedUIStringValue,
                    label: row.label,
                    frame: DisplayedUIFrame(row.frame)
                )
            )
        }
        return rows.sorted(by: displayedUITopToBottomOrder)
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
        let root = displayedUIWaitForElement(identifierPrefix: "codexdock.session.root.", timeout: 0.1)
        guard let root, root.exists else {
            return nil
        }
        let rootValue = root.displayedUIStringValue
        let rootCapturedAt = codexDockISO8601Now()
        let messageCards = elementSnapshots(prefix: "codexdock.session.message.", in: root)
        let messageCardsCapturedAt = codexDockISO8601Now()
        let requestElements = elementSnapshots(prefix: "codexdock.session.request.", in: root)
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
            messageCardIDs: messageCards.map(\.identifier),
            requestElementsCapturedAt: requestElementsCapturedAt,
            requestCardIDs: requestElements.map(\.identifier),
            messageCards: messageCards,
            requestElements: requestElements
        )
    }

    private func optionalStringValue(id: String) -> String {
        let target = displayedUIElement(id: id)
        return target.exists ? target.displayedUIStringValue : "not-visible"
    }

    private func elementSnapshots(prefix: String) -> [DisplayedUIElementSnapshot] {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        return elementSnapshots(matching: descendants(matching: .any).matching(predicate))
    }

    private func elementSnapshots(prefix: String, in root: XCUIElement) -> [DisplayedUIElementSnapshot] {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        return elementSnapshots(matching: root.descendants(matching: .any).matching(predicate))
    }

    private func elementSnapshots(matching query: XCUIElementQuery) -> [DisplayedUIElementSnapshot] {
        let elements = query.allElementsBoundByIndex
        var snapshots: [DisplayedUIElementSnapshot] = []
        var seen = Set<String>()
        for element in elements.prefix(120) {
            let identifier = element.identifier
            guard seen.insert(identifier).inserted else {
                continue
            }
            let value = element.displayedUIStringValue
            let label = element.label
            let frame = DisplayedUIFrame(element.frame)
            snapshots.append(
                DisplayedUIElementSnapshot(
                    identifier: identifier,
                    capturedAt: codexDockISO8601Now(),
                    value: value,
                    label: label,
                    frame: frame
                )
            )
        }
        // Displayed-UI proof must preserve visual order. Sorting by identifier
        // hides the exact class of newest-first bugs this harness exists to catch.
        return snapshots.sorted(by: displayedUITopToBottomOrder)
    }

    private func displayedUITopToBottomOrder(_ left: DisplayedUIDockRow, _ right: DisplayedUIDockRow) -> Bool {
        displayedUITopToBottomOrder(left.frame, right.frame, left.identifier, right.identifier)
    }

    private func displayedUITopToBottomOrder(_ left: DisplayedUIElementSnapshot, _ right: DisplayedUIElementSnapshot) -> Bool {
        displayedUITopToBottomOrder(left.frame, right.frame, left.identifier, right.identifier)
    }

    private func displayedUITopToBottomOrder(
        _ leftFrame: DisplayedUIFrame,
        _ rightFrame: DisplayedUIFrame,
        _ leftIdentifier: String,
        _ rightIdentifier: String
    ) -> Bool {
        let verticalTolerance = 1.0
        if abs(leftFrame.minY - rightFrame.minY) > verticalTolerance {
            return leftFrame.minY < rightFrame.minY
        }
        if leftFrame.minX != rightFrame.minX {
            return leftFrame.minX < rightFrame.minX
        }
        return leftIdentifier < rightIdentifier
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
func elementExists(_ element: XCUIElement) -> Bool {
    element.exists
}

extension XCUIElementQuery {
    var firstMatchIfExists: XCUIElement? {
        let candidate = firstMatch
        return candidate.exists ? candidate : nil
    }
}

func codexDockISO8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

func codexDockAutomationField(_ name: String, in value: String) -> String? {
    let prefix = "\(name)="
    for part in value.split(separator: ";", omittingEmptySubsequences: false) {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else {
            continue
        }
        return String(trimmed.dropFirst(prefix.count))
    }
    return nil
}

extension XCUIElement {
    var displayedUIStringValue: String {
        if let value = self.value as? String {
            return value
        }
        return label
    }

    func waitForDisplayedUIStringValue(containing expected: String, timeout: TimeInterval) -> Bool {
        waitForDisplayedUIStringValue(matching: { $0.contains(expected) }, timeout: timeout)
    }

    func waitForDisplayedUIStringValue(matching predicate: (String) -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(displayedUIStringValue) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}

extension XCUIApplication.State {
    var codexDockName: String {
        switch self {
        case .notRunning:
            return "notRunning"
        case .runningBackgroundSuspended:
            return "runningBackgroundSuspended"
        case .runningBackground:
            return "runningBackground"
        case .runningForeground:
            return "runningForeground"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
