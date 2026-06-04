import CodexDock
import Foundation
import XCTest

@MainActor
final class CodexDockUserMessageLatencyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testControlledUserMessageSendIsNonBlockingWhenConfigured() throws {
        let config = try UserMessageLatencyProofConfig.loadFromEnvironment()
        let startedAt = codexDockISO8601Now()
        let app = launchRelayBackedApp(hosts: config.hosts)

        func writeResult(
            status: DisplayedUIArtifactStatus,
            reason: String?,
            timings: UserMessageLatencyUITimings? = nil,
            composerValueAfter: String? = nil,
            messageListValueAfter: String? = nil,
            keyboardVisibleBeforeSend: Bool? = nil,
            keyboardVisibleAfterSend: Bool? = nil,
            rawAccessibilityTree: String? = nil
        ) throws {
            let report = UserMessageLatencyUIReport(
                status: status,
                reason: reason,
                startedAt: startedAt,
                finishedAt: codexDockISO8601Now(),
                hosts: config.hosts,
                hostID: config.hostID,
                threadID: config.threadID,
                messageText: config.messageText,
                upstreamAckDelayMS: config.upstreamAckDelayMS,
                uiBudgetMS: config.uiBudgetMS,
                timings: timings,
                composerValueAfter: composerValueAfter,
                messageListValueAfter: messageListValueAfter,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: keyboardVisibleAfterSend,
                rawAccessibilityTree: rawAccessibilityTree
            )
            try report.write(to: config.uiResultPath)
            for mirrorPath in UserMessageLatencyProofConfig.uiResultMirrorPaths(primaryPath: config.uiResultPath) {
                try? report.write(to: mirrorPath)
            }
            if status != .pass {
                XCTFail(reason ?? "User message latency proof failed.")
            }
        }

        guard app.element(id: AutomationID.Dock.searchField).waitForExistence(timeout: 20),
              app.element(id: AutomationID.Dock.root).waitForDisplayedUIStringValue(containing: "loaded;", timeout: 30) else {
            try writeResult(
                status: .blocked,
                reason: "Dock did not reach loaded state before user-message latency proof.",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        app.collapsePinnedSectionIfExpandedForUserMessageProof()

        guard let rowID = app.tapFirstVisibleButtonForUserMessageProof(
            identifierPrefix: "codexdock.dock.row.",
            excludedIdentifierParts: [".action.", ".actions"],
            timeout: 25
        ) else {
            try writeResult(
                status: .blocked,
                reason: "No controlled Dock row was visible before user-message latency proof.",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        XCTAssertTrue(rowID.contains(config.threadID), "Opened row did not contain expected thread id \(config.threadID). row=\(rowID)")

        guard app.waitForLoadedSessionRootForUserMessageProof(threadID: config.threadID, timeout: 30) != nil else {
            try writeResult(
                status: .blocked,
                reason: "Thread Detail did not reach loaded state before user-message latency proof.",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        let messageField = app.element(id: AutomationID.Composer.messageField)
        let sendButton = app.element(id: AutomationID.Composer.sendButton)
        guard app.waitUntilHittableForUserMessageProof(messageField, timeout: 10),
              app.waitUntilHittableForUserMessageProof(sendButton, timeout: 10) else {
            try writeResult(
                status: .blocked,
                reason: "Composer controls were not hittable before user-message latency proof.",
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        messageField.tap()
        messageField.typeText(config.messageText)
        guard sendButton.waitForDisplayedUIStringValue(containing: "enabled", timeout: 5) else {
            try writeResult(
                status: .blocked,
                reason: "Send button did not become enabled after typing the proof message.",
                composerValueAfter: app.element(id: AutomationID.Composer.root).displayedUIStringValue,
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        let tappedAtMs = monotonicMilliseconds()
        let tappedAt = codexDockISO8601Now()
        let keyboardVisibleBeforeSend = app.softwareKeyboardVisibleForUserMessageProof()
        sendButton.tap()

        let composerRoot = app.element(id: AutomationID.Composer.root)
        let messageList = app.element(id: AutomationID.Session.messageList)
        let budgetObservations = app.observeUserMessageProofBudget(
            composerRoot: composerRoot,
            messageList: messageList,
            keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
            tappedAt: tappedAt,
            tappedAtMs: tappedAtMs,
            timeoutMS: config.uiBudgetMS
        )
        let canonicalObserved = app.waitForUserMessageProof(timeout: 12) {
            messageList.exists
                && messageList.displayedUIStringValue.contains("item-user-proof")
                && !messageList.displayedUIStringValue.contains("pending%3A")
        }

        let timings = UserMessageLatencyUITimings(
            sendTappedAt: tappedAt,
            sendTappedAtMs: tappedAtMs,
            composerFocusClearedAt: budgetObservations.composerFocusCleared?.at,
            composerFocusClearedAtMs: budgetObservations.composerFocusCleared?.atMs,
            composerFocusClearMS: budgetObservations.composerFocusCleared.map { Int($0.atMs - tappedAtMs) } ?? Int.max,
            composerClearedAt: budgetObservations.composerCleared?.at,
            composerClearedAtMs: budgetObservations.composerCleared?.atMs,
            composerClearMS: budgetObservations.composerCleared.map { Int($0.atMs - tappedAtMs) } ?? Int.max,
            pendingObservedAt: budgetObservations.pendingObserved?.at,
            pendingObservedAtMs: budgetObservations.pendingObserved?.atMs,
            pendingObservedMS: budgetObservations.pendingObserved.map { Int($0.atMs - tappedAtMs) } ?? Int.max,
            canonicalObservedAt: canonicalObserved?.at,
            canonicalObservedAtMs: canonicalObserved?.atMs,
            canonicalObservedMS: canonicalObserved.map { Int($0.atMs - tappedAtMs) } ?? Int.max,
            keyboardDismissedAt: budgetObservations.keyboardDismissed?.at,
            keyboardDismissedAtMs: budgetObservations.keyboardDismissed?.atMs,
            keyboardDismissMS: budgetObservations.keyboardDismissed.map { Int($0.atMs - tappedAtMs) } ?? Int.max
        )

        if timings.composerFocusClearMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Composer focus cleared in \(timings.composerFocusClearMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                composerValueAfter: composerRoot.displayedUIStringValue,
                messageListValueAfter: messageList.displayedUIStringValue,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof(),
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        if keyboardVisibleBeforeSend && timings.keyboardDismissMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Software keyboard dismissed in \(timings.keyboardDismissMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                composerValueAfter: composerRoot.displayedUIStringValue,
                messageListValueAfter: messageList.displayedUIStringValue,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof(),
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        if timings.composerClearMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Composer cleared in \(timings.composerClearMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                composerValueAfter: composerRoot.displayedUIStringValue,
                messageListValueAfter: messageList.displayedUIStringValue,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof(),
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        if timings.pendingObservedMS > config.uiBudgetMS {
            try writeResult(
                status: .fail,
                reason: "Pending outbound row appeared in \(timings.pendingObservedMS) ms, over budget \(config.uiBudgetMS) ms.",
                timings: timings,
                composerValueAfter: composerRoot.displayedUIStringValue,
                messageListValueAfter: messageList.displayedUIStringValue,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof(),
                rawAccessibilityTree: app.debugDescription
            )
            return
        }
        guard canonicalObserved != nil else {
            try writeResult(
                status: .fail,
                reason: "Canonical user-message row did not replace the pending row after upstream acknowledgement.",
                timings: timings,
                composerValueAfter: composerRoot.displayedUIStringValue,
                messageListValueAfter: messageList.displayedUIStringValue,
                keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
                keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof(),
                rawAccessibilityTree: app.debugDescription
            )
            return
        }

        try writeResult(
            status: .pass,
            reason: nil,
            timings: timings,
            composerValueAfter: composerRoot.displayedUIStringValue,
            messageListValueAfter: messageList.displayedUIStringValue,
            keyboardVisibleBeforeSend: keyboardVisibleBeforeSend,
            keyboardVisibleAfterSend: app.softwareKeyboardVisibleForUserMessageProof()
        )
    }

    private func launchRelayBackedApp(hosts: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
        app.launch()
        return app
    }
}

private struct UserMessageLatencyProofConfig: Decodable {
    let hosts: String
    let hostID: String
    let threadID: String
    let messageText: String
    let uiResultPath: String
    let upstreamAckDelayMS: Int
    let uiBudgetMS: Int

    static let defaultReadyPath = "/tmp/codex-client/codex-dock-user-message-proof-ready.json"
    static let defaultUIResultPath = "/tmp/codex-client/codex-dock-user-message-latency-ui.json"

    static func loadFromEnvironment() throws -> UserMessageLatencyProofConfig {
        let environment = ProcessInfo.processInfo.environment
        let readyPath = nonEmpty(environment["CODEX_DOCK_USER_MESSAGE_PROOF_READY"])
            ?? defaultReadyPath
        guard FileManager.default.fileExists(atPath: readyPath) else {
            throw XCTSkip("Controlled user-message latency ready file does not exist at \(readyPath).")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: readyPath))
        return try JSONDecoder().decode(UserMessageLatencyProofConfig.self, from: data)
    }

    static func uiResultMirrorPaths(primaryPath: String) -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let paths = [
            nonEmpty(environment["CODEX_DOCK_USER_MESSAGE_PROOF_UI_RESULT_HOST"]),
            defaultUIResultPath,
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

private struct UserMessageLatencyUITimings: Codable {
    var sendTappedAt: String
    var sendTappedAtMs: Int64
    var composerFocusClearedAt: String?
    var composerFocusClearedAtMs: Int64?
    var composerFocusClearMS: Int
    var composerClearedAt: String?
    var composerClearedAtMs: Int64?
    var composerClearMS: Int
    var pendingObservedAt: String?
    var pendingObservedAtMs: Int64?
    var pendingObservedMS: Int
    var canonicalObservedAt: String?
    var canonicalObservedAtMs: Int64?
    var canonicalObservedMS: Int
    var keyboardDismissedAt: String?
    var keyboardDismissedAtMs: Int64?
    var keyboardDismissMS: Int
}

private struct UserMessageLatencyUIReport: Codable {
    var schemaVersion = 1
    var kind = "codex-dock-user-message-latency-ui-proof"
    var status: DisplayedUIArtifactStatus
    var reason: String?
    var startedAt: String
    var finishedAt: String
    var hosts: String
    var hostID: String
    var threadID: String
    var messageText: String
    var upstreamAckDelayMS: Int
    var uiBudgetMS: Int
    var timings: UserMessageLatencyUITimings?
    var composerValueAfter: String?
    var messageListValueAfter: String?
    var keyboardVisibleBeforeSend: Bool?
    var keyboardVisibleAfterSend: Bool?
    var rawAccessibilityTree: String?

    func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}

private struct UserMessageLatencyUIObservation {
    let at: String
    let atMs: Int64

    static func now() -> UserMessageLatencyUIObservation {
        UserMessageLatencyUIObservation(
            at: codexDockISO8601Now(),
            atMs: monotonicMilliseconds()
        )
    }
}

private struct UserMessageLatencyUIBudgetObservations {
    var composerFocusCleared: UserMessageLatencyUIObservation?
    var composerCleared: UserMessageLatencyUIObservation?
    var pendingObserved: UserMessageLatencyUIObservation?
    var keyboardDismissed: UserMessageLatencyUIObservation?
}

@MainActor
private extension XCUIApplication {
    func element(id: AutomationID) -> XCUIElement {
        element(id: id.rawValue)
    }

    func element(id: String) -> XCUIElement {
        descendants(matching: .any)[id]
    }

    func tapFirstVisibleButtonForUserMessageProof(
        identifierPrefix: String,
        excludedIdentifierParts: [String],
        timeout: TimeInterval
    ) -> String? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let query = buttons.matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for index in 0..<30 {
                let element = query.element(boundBy: index)
                guard element.exists else {
                    break
                }
                let identifier = element.identifier
                guard !excludedIdentifierParts.contains(where: { identifier.contains($0) }) else {
                    continue
                }
                guard isVisibleForUserMessageTap(element.frame), element.isHittable else {
                    continue
                }
                element.tap()
                return identifier
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    func waitForLoadedSessionRootForUserMessageProof(threadID: String, timeout: TimeInterval) -> XCUIElement? {
        let root = element(id: AutomationID.Session.root(threadID: threadID))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if root.exists, root.displayedUIStringValue.contains("loaded;") {
                return root
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    func waitUntilHittableForUserMessageProof(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable, isVisibleForUserMessageTap(element.frame) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    func waitForUserMessageProof(timeout: TimeInterval, predicate: () -> Bool) -> UserMessageLatencyUIObservation? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return UserMessageLatencyUIObservation(
                    at: codexDockISO8601Now(),
                    atMs: monotonicMilliseconds()
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    func observeUserMessageProofBudget(
        composerRoot: XCUIElement,
        messageList: XCUIElement,
        keyboardVisibleBeforeSend: Bool,
        tappedAt: String,
        tappedAtMs: Int64,
        timeoutMS: Int
    ) -> UserMessageLatencyUIBudgetObservations {
        var observations = UserMessageLatencyUIBudgetObservations(
            keyboardDismissed: keyboardVisibleBeforeSend
                ? nil
                : UserMessageLatencyUIObservation(at: tappedAt, atMs: tappedAtMs)
        )
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1_000.0)
        while Date() < deadline {
            let observedAt = UserMessageLatencyUIObservation.now()
            if composerRoot.exists {
                let composerValue = composerRoot.displayedUIStringValue
                if observations.composerFocusCleared == nil,
                   composerValue.contains("message-focused=false") {
                    observations.composerFocusCleared = observedAt
                }
                if observations.composerCleared == nil,
                   composerValue.contains("can-send=false"),
                   composerValue.contains("sending=false") {
                    observations.composerCleared = observedAt
                }
            }
            if observations.keyboardDismissed == nil,
               !softwareKeyboardVisibleForUserMessageProof() {
                observations.keyboardDismissed = observedAt
            }
            if observations.pendingObserved == nil, messageList.exists {
                let messageListValue = messageList.displayedUIStringValue
                if messageListValue.contains("pending%3A"),
                   messageListValue.contains("events=1") {
                    observations.pendingObserved = observedAt
                }
            }
            if observations.composerFocusCleared != nil,
               observations.composerCleared != nil,
               observations.pendingObserved != nil,
               observations.keyboardDismissed != nil {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return observations
    }

    func softwareKeyboardVisibleForUserMessageProof() -> Bool {
        keyboards.firstMatch.exists
    }

    func collapsePinnedSectionIfExpandedForUserMessageProof() {
        let toggle = element(id: "codexdock.dock.section.pinned.toggle")
        guard toggle.exists, toggle.displayedUIStringValue.contains("expanded") else {
            return
        }
        toggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}

private func isVisibleForUserMessageTap(_ frame: CGRect) -> Bool {
    frame.width > 1
        && frame.height > 1
        && frame.maxX > 0
        && frame.maxY > 0
        && frame.minX < 500
        && frame.minY < 1_200
}

private func monotonicMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
}
