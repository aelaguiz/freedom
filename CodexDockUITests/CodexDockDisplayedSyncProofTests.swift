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
                app.displayedUIWaitForElement(identifierPrefix: AutomationID.Session.root(threadID: openThreadID).rawValue, timeout: 15),
                "Displayed sync proof did not reach target thread detail for \(openThreadID)."
            )
            if let detailFilter = config.detailFilter {
                XCTAssertTrue(
                    app.selectMessageFilter(detailFilter, timeout: 10),
                    "Displayed sync proof could not switch the real detail filter to \(detailFilter)."
                )
            }

            try DisplayedUIArtifactWriter.markReady(to: config.readyPath)

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
            try DisplayedUIArtifactWriter.markReady(to: config.readyPath)

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
        }

        if config.openThreadID != nil, config.checkpointSweep == true {
            if let backButton = app.navigationBars.buttons.firstMatchIfExists {
                backButton.tap()
                if root.waitForDisplayedUIStringValue(matching: { value in
                    value.contains("loaded") && !value.contains("Partial")
                }, timeout: 10) {
                    samples.append(app.captureDisplayedUISample(index: sampleIndex, includeDockSweep: true))
                    sampleIndex += 1
                }
            } else if elementExists(app.displayedUIElement(id: AutomationID.Dock.root.rawValue)) {
                samples.append(app.captureDisplayedUISample(index: sampleIndex))
                sampleIndex += 1
            }
        }

        XCTAssertFalse(samples.isEmpty, "Displayed sync proof did not record any UI samples.")
        XCTAssertTrue(
            samples.contains(where: { $0.dockRootValue.contains("loaded") }),
            "Displayed sync proof never observed the Dock loaded state."
        )

        try DisplayedUIArtifactWriter.writeSamples(samples, to: config.outputPath)
        add(XCTAttachment(string: samples.map(\.jsonLine).joined(separator: "\n")))
    }

    private func launchRelayBackedApp(hosts: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
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
