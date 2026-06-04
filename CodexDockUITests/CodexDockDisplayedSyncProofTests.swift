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

        let startIdentifier = app.displayedUIWaitForFirstIdentifier([
            AutomationID.Dock.root.rawValue,
            AutomationID.Bootstrap.manualHostField.rawValue,
        ], timeout: 30)
        XCTAssertEqual(
            startIdentifier,
            AutomationID.Dock.root.rawValue,
            "Displayed sync proof must start on the relay-backed Dock UI, not the bootstrap form.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        let root = app.displayedUIElement(id: AutomationID.Dock.root.rawValue)
        XCTAssertTrue(
            root.waitForDisplayedUIStringValue(matching: { value in
                value.contains("loaded") && !value.contains("Partial")
            }, timeout: 30),
            "Dock did not reach complete loaded state before sampling. Root value: \(root.displayedUIStringValue)"
        )

        try DisplayedUIArtifactWriter.resetSamples(at: config.outputPath)
        var sampleCount = 0
        var observedLoadedDock = false
        var sampleIndex = 0
        func captureSample(
            index: Int,
            includeDockSweep: Bool = false,
            includeDetailSweep: Bool = false
        ) -> DisplayedUISample {
            app.captureDisplayedUISample(
                index: index,
                includeDockSweep: includeDockSweep,
                includeDetailSweep: includeDetailSweep,
                includeDetailRequestElements: false,
                configuredHostIDs: config.resolvedHostIDs
            )
        }
        func record(_ sample: DisplayedUISample) throws {
            sampleCount += 1
            observedLoadedDock = observedLoadedDock || sample.dockRootValue.contains("loaded")
            try DisplayedUIArtifactWriter.appendSample(sample, to: config.outputPath)
        }

        if let openThreadID = config.openThreadID {
            let firstSampleStartedAt = Date()
            try record(captureSample(index: sampleIndex))
            sampleIndex += 1
            waitUntilNextSample(startedAt: firstSampleStartedAt, sampleMS: config.sampleMS)
            try record(captureSample(index: sampleIndex))
            sampleIndex += 1

            guard let row = app.visibleDockRow(hostID: config.openHostID, threadID: openThreadID, timeout: 15) else {
                XCTFail("Displayed sync proof could not find target Dock row host=\(config.openHostID ?? "*") thread=\(openThreadID).\n\nAccessibility tree:\n\(app.debugDescription)")
                return
            }
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertNotNil(
                app.displayedUIWaitForElement(identifierPrefix: AutomationID.Session.root(threadID: openThreadID).rawValue, timeout: 15),
                "Displayed sync proof did not reach target thread detail for \(openThreadID)."
            )
            if let detailFilter = config.detailFilter {
                XCTAssertTrue(
                    app.selectMessageFilter(detailFilter, timeout: 10),
                    "Displayed sync proof could not switch the real detail filter to \(detailFilter)."
                )
            }
            _ = app.scrollDetailMessagesIntoEvidencePosition(timeout: 5)
            let detailReadySampleStartedAt = Date()
            let detailReadySample = captureSample(index: sampleIndex)
            XCTAssertNotNil(
                detailReadySample.detail,
                "Displayed sync proof must capture a real Thread Detail sample before allowing the controlled fixture to emit detail mutations."
            )
            try record(detailReadySample)
            sampleIndex += 1
            waitUntilNextSample(startedAt: detailReadySampleStartedAt, sampleMS: config.sampleMS)

            if config.foregroundCycleBeforeReady == true {
                XCUIDevice.shared.press(.home)
                RunLoop.current.run(until: Date().addingTimeInterval(0.75))
                try DisplayedUIArtifactWriter.markReady(to: config.readyPath)
                let delay = TimeInterval(config.foregroundResumeDelayMS ?? config.sampleMS) / 1000.0
                RunLoop.current.run(until: Date().addingTimeInterval(max(0.1, delay)))
                app.activate()
                XCTAssertNotNil(
                    app.displayedUIWaitForElement(identifierPrefix: AutomationID.Session.root(threadID: openThreadID).rawValue, timeout: 15),
                    "Displayed sync proof did not return to target thread detail after the foreground cycle for \(openThreadID)."
                )
            } else {
                try DisplayedUIArtifactWriter.markReady(to: config.readyPath)
            }

            let deadline = Date().addingTimeInterval(TimeInterval(config.durationMS) / 1000.0)
            var didTapRequestAction = false
            var didCompleteFileChangeReview = false
            repeat {
                let sampleStartedAt = Date()
                let sample = captureSample(index: sampleIndex)
                try record(sample)
                sampleIndex += 1
                if !didTapRequestAction,
                   let action = config.requestAction,
                   let detail = sample.detail {
                    if let cardID = config.requestCardID,
                       detail.containsRequestCard(cardID: cardID) == true,
                       // Do not mutate a controlled request until the UI dump
                       // has proved the same relay projection row is visible.
                       detail.containsMessageCard(projectionID: cardID) == true,
                       app.tapRequestAction(cardID: cardID, action: action, timeout: 0.2) {
                        didTapRequestAction = true
                    } else if config.requestCardID == nil,
                              app.tapFirstRequestAction(
                        requestElementIdentifiers: detail.requestCardIDs,
                        action: action,
                        timeout: 0.2
                    ) {
                        didTapRequestAction = true
                    }
                }
                if !didCompleteFileChangeReview,
                   let eventID = config.fileChangeReviewEventID,
                   let fileID = config.fileChangeReviewFileID,
                   let requestCardID = config.fileChangeReviewRequestCardID,
                   let detail = sample.detail,
                   detail.containsMessageCard(projectionID: eventID) == true {
                    let requestPrefix = AutomationID.RequestCard.card(cardID: requestCardID).rawValue
                    let requestVisible = detail.requestCardIDs.contains { identifier in
                        identifier == requestPrefix || identifier.hasPrefix("\(requestPrefix).")
                    } || detail.requestStatus(cardID: requestCardID) != nil
                    if requestVisible,
                       app.completeFileChangeReviewFlow(
                        eventID: eventID,
                        fileID: fileID,
                        requestCardID: requestCardID,
                        timeout: 5
                       ) {
                        didCompleteFileChangeReview = true
                    }
                }
                waitUntilNextSample(startedAt: sampleStartedAt, sampleMS: config.sampleMS)
            } while Date() < deadline

            if config.detailCheckpointSweep == true {
                try record(captureSample(index: sampleIndex, includeDetailSweep: true))
                sampleIndex += 1
            }
        } else {
            try DisplayedUIArtifactWriter.markReady(to: config.readyPath)

            let deadline = Date().addingTimeInterval(TimeInterval(config.durationMS) / 1000.0)
            let dockLenses = config.resolvedDockLenses
            repeat {
                let sampleStartedAt = Date()
                let lens = dockLenses[sampleIndex % dockLenses.count]
                XCTAssertTrue(
                    selectDockLens(lens, app: app, root: root),
                    "Displayed sync proof could not switch Dock lens to \(lens.rawValue)."
                )
                try record(captureSample(index: sampleIndex))
                sampleIndex += 1
                waitUntilNextSample(startedAt: sampleStartedAt, sampleMS: config.sampleMS)
            } while Date() < deadline

            if config.checkpointSweep == true {
                try record(captureSample(index: sampleIndex, includeDockSweep: true))
                sampleIndex += 1
            }
        }

        if config.openThreadID != nil, config.checkpointSweep == true {
            if let backButton = app.navigationBars.buttons.firstMatchIfExists {
                backButton.tap()
                if root.waitForDisplayedUIStringValue(matching: { value in
                    value.contains("loaded") && !value.contains("Partial")
                }, timeout: 10) {
                    try record(captureSample(index: sampleIndex, includeDockSweep: true))
                    sampleIndex += 1
                }
            } else if elementExists(app.displayedUIElement(id: AutomationID.Dock.root.rawValue)) {
                try record(captureSample(index: sampleIndex))
                sampleIndex += 1
            }
        }

        XCTAssertGreaterThan(sampleCount, 0, "Displayed sync proof did not record any UI samples.")
        XCTAssertTrue(
            observedLoadedDock,
            "Displayed sync proof never observed the Dock loaded state."
        )
    }

    private func launchRelayBackedApp(hosts: String) -> XCUIApplication {
        launchRelayBackedCodexDockApp(hosts: hosts, terminateFirst: true)
    }

    private func selectDockLens(
        _ lens: DockLensID,
        app: XCUIApplication,
        root: XCUIElement
    ) -> Bool {
        if root.displayedUIStringValue.contains("lens=\(lens.rawValue)") {
            return true
        }
        app.displayedUIElement(id: AutomationID.Dock.lensButton(lens.rawValue).rawValue)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        return root.waitForDisplayedUIStringValue(
            matching: { $0.contains("lens=\(lens.rawValue)") },
            timeout: 5
        )
    }

    private func waitUntilNextSample(startedAt: Date, sampleMS: Int) {
        let target = startedAt.addingTimeInterval(TimeInterval(sampleMS) / 1000.0)
        guard target > Date() else {
            return
        }
        RunLoop.current.run(until: target)
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
    var dockLenses: [String]?
    var foregroundCycleBeforeReady: Bool?
    var foregroundResumeDelayMS: Int?
    var fileChangeReviewEventID: String?
    var fileChangeReviewFileID: String?
    var fileChangeReviewRequestCardID: String?

    var resolvedHostIDs: [String] {
        hosts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var resolvedDockLenses: [DockLensID] {
        let parsed = (dockLenses ?? [DockLensID.newest.rawValue])
            .compactMap(DockLensID.init(rawValue:))
        return parsed.isEmpty ? [.newest] : parsed
    }

    // The Makefile proof targets serialize this single simulator config path
    // with codex-dock-sim-ui-sync-config.lock. Keep this one path canonical so
    // UI proof runs cannot silently drift through per-process overrides.
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
