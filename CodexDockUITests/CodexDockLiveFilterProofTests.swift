import CodexDock
import XCTest

@MainActor
final class CodexDockLiveFilterProofTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSamplesRealThreadDetailFiltersOverTime() throws {
        let config = try LiveFilterProofConfig.load()
        let app = launchRelayBackedApp(hosts: config.hosts)

        let startIdentifier = app.displayedUIWaitForFirstIdentifier([
            AutomationID.Dock.root.rawValue,
            AutomationID.Bootstrap.manualHostField.rawValue,
        ], timeout: 30)
        XCTAssertEqual(
            startIdentifier,
            AutomationID.Dock.root.rawValue,
            "Live filter proof must start on the relay-backed Dock UI, not bootstrap.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        let root = app.displayedUIElement(id: AutomationID.Dock.root.rawValue)
        XCTAssertTrue(
            root.waitForDisplayedUIStringValue(matching: { value in
                value.contains("loaded") && !value.contains("Partial")
            }, timeout: 30),
            "Dock did not reach complete loaded state before live filter sampling. Root value: \(root.displayedUIStringValue)"
        )

        guard let row = app.visibleDockRow(hostID: config.openHostID, threadID: config.openThreadID, timeout: 20) else {
            XCTFail("Live filter proof could not find target Dock row host=\(config.openHostID ?? "*") thread=\(config.openThreadID).\n\nAccessibility tree:\n\(app.debugDescription)")
            return
        }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertNotNil(
            app.displayedUIWaitForElement(identifierPrefix: AutomationID.Session.root(threadID: config.openThreadID).rawValue, timeout: 20),
            "Live filter proof did not reach target thread detail for \(config.openThreadID)."
        )

        var filterRuns: [LiveFilterRun] = []
        var sampleIndex = 0
        for filter in config.filters {
            XCTAssertTrue(
                app.selectMessageFilter(filter, timeout: 10),
                "Live filter proof could not select Thread Detail filter \(filter)."
            )

            var samples: [LiveFilterSample] = []
            let deadline = Date().addingTimeInterval(TimeInterval(config.dwellMS) / 1000.0)
            repeat {
                samples.append(app.liveFilterSample(index: sampleIndex, filter: filter))
                sampleIndex += 1
                RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(config.sampleMS) / 1000.0))
            } while Date() < deadline

            samples.append(app.liveFilterSample(index: sampleIndex, filter: filter, includeDetailSweep: true))
            sampleIndex += 1
            filterRuns.append(
                LiveFilterRun(
                    filter: filter,
                    selectedAt: codexDockISO8601Now(),
                    samples: samples
                )
            )
        }

        let report = LiveFilterProofReport(
            status: .pass,
            capturedAt: filterRuns.first?.samples.first?.sampledAt ?? codexDockISO8601Now(),
            finishedAt: codexDockISO8601Now(),
            hosts: config.hosts,
            openHostID: config.openHostID,
            openThreadID: config.openThreadID,
            filters: config.filters,
            dwellMS: config.dwellMS,
            sampleMS: config.sampleMS,
            runs: filterRuns
        )
        try report.write(to: config.outputPath)
    }

    private func launchRelayBackedApp(hosts: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
        app.terminate()
        app.launch()
        return app
    }
}

private extension XCUIApplication {
    func liveFilterSample(
        index: Int,
        filter: String,
        includeDetailSweep: Bool = false
    ) -> LiveFilterSample {
        let displayed = captureDisplayedUISample(index: index, includeDetailSweep: includeDetailSweep)
        return LiveFilterSample(
            sampleIndex: index,
            sampledAt: displayed.sampledAt,
            finishedAt: displayed.finishedAt,
            screenKind: displayed.screenKind.rawValue,
            filter: filter,
            detailRootValue: displayed.detail?.rootValue ?? "not-visible",
            messageListValue: displayed.detail?.messageListValue ?? "not-visible",
            messageCards: (displayed.detail?.messageCards ?? []).map(LiveFilterElement.init(snapshot:)),
            requestElements: (displayed.detail?.requestElements ?? []).map(LiveFilterElement.init(snapshot:)),
            sweepMessageCards: (displayed.detailSweep?.messageCards ?? []).map(LiveFilterElement.init(snapshot:)),
            sweepRequestElements: (displayed.detailSweep?.requestElements ?? []).map(LiveFilterElement.init(snapshot:))
        )
    }
}

private struct LiveFilterProofConfig: Codable {
    var outputPath: String
    var hosts: String
    var openHostID: String?
    var openThreadID: String
    var filters: [String]
    var dwellMS: Int
    var sampleMS: Int
    var expiresAt: String

    static let path = "/tmp/codex-client/codex-dock-live-filter-config.json"

    static func load() throws -> LiveFilterProofConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Create \(path) to run the live real-data filter proof.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try JSONDecoder().decode(LiveFilterProofConfig.self, from: data)
        guard let expiry = ISO8601DateFormatter().date(from: config.expiresAt), expiry > Date() else {
            throw XCTSkip("Live filter proof config at \(path) is expired.")
        }
        return config
    }
}

private struct LiveFilterProofReport: Codable {
    var schemaVersion: Int = 1
    var kind: String = "codex-dock-live-filter-proof"
    var status: DisplayedUIArtifactStatus
    var capturedAt: String
    var finishedAt: String
    var hosts: String
    var openHostID: String?
    var openThreadID: String
    var filters: [String]
    var dwellMS: Int
    var sampleMS: Int
    var runs: [LiveFilterRun]

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

private struct LiveFilterRun: Codable {
    var filter: String
    var selectedAt: String
    var samples: [LiveFilterSample]
}

private struct LiveFilterSample: Codable {
    var sampleIndex: Int
    var sampledAt: String
    var finishedAt: String
    var screenKind: String
    var filter: String
    var detailRootValue: String
    var messageListValue: String
    var messageCards: [LiveFilterElement]
    var requestElements: [LiveFilterElement]
    var sweepMessageCards: [LiveFilterElement]
    var sweepRequestElements: [LiveFilterElement]
}

private struct LiveFilterElement: Codable {
    var identifier: String
    var value: String

    init(snapshot: DisplayedUIElementSnapshot) {
        self.identifier = snapshot.identifier
        self.value = snapshot.value
    }
}
