import XCTest

@MainActor
final class CodexDockCurrentUIDumpTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDumpsCurrentVisibleScreenOnce() throws {
        if !FileManager.default.fileExists(atPath: DisplayedUICurrentDumpConfig.path) {
            let fallback = DisplayedUICurrentDumpConfig.fallback()
            try writeBlockedDump(
                config: fallback,
                reason: "Missing dump config at \(DisplayedUICurrentDumpConfig.path); use rtk make sim-ui-dump."
            )
            guard DisplayedUICurrentDumpConfig.requiresConfiguredRun else {
                throw XCTSkip("Create \(DisplayedUICurrentDumpConfig.path) through rtk make sim-ui-dump.")
            }
            XCTFail("Missing dump config at \(DisplayedUICurrentDumpConfig.path); use rtk make sim-ui-dump.")
            return
        }

        let config: DisplayedUICurrentDumpConfig
        do {
            config = try DisplayedUICurrentDumpConfig.load()
        } catch {
            let fallback = DisplayedUICurrentDumpConfig.fallback()
            try writeBlockedDump(
                config: fallback,
                reason: "Missing or invalid dump config at \(DisplayedUICurrentDumpConfig.path): \(error)"
            )
            XCTFail("Missing or invalid dump config at \(DisplayedUICurrentDumpConfig.path): \(error)")
            return
        }

        let app = XCUIApplication(bundleIdentifier: config.appBundleID)
        let stateBefore = app.state
        guard stateBefore != .notRunning else {
            try writeBlockedDump(
                config: config,
                reason: "\(config.appBundleID) is not running; dump mode must not launch the app."
            )
            XCTFail("\(config.appBundleID) is not running; dump mode must not launch the app.")
            return
        }

        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let sampleBefore = app.captureDisplayedUISample(index: 0)
        let screenBefore = app.visibleScreenKind(from: sampleBefore)
        let sampleAfter = app.captureDisplayedUISample(index: 1)
        let screenAfter = app.visibleScreenKind(from: sampleAfter)
        let stateAfter = app.state
        let visibleElements = app.visibleAccessibilityElements()

        var status: DisplayedUIArtifactStatus = .pass
        var reason: String?

        if stateAfter != .runningForeground {
            status = .blocked
            reason = "\(config.appBundleID) did not activate to the foreground; stateAfter=\(stateAfter.codexDockName)."
        } else if screenAfter == .unknown {
            status = .blocked
            reason = "Visible screen is unknown; JSON includes raw accessibility tree for diagnosis."
        } else if screenBefore != screenAfter {
            status = .fail
            reason = "Screen changed during dump: \(screenBefore.rawValue) -> \(screenAfter.rawValue)."
        } else if sampleAfter.dockRootValue.contains("loaded"),
                  codexDockAutomationField("automationSnapshotPath", in: sampleAfter.dockRootValue) == nil,
                  sampleAfter.dockRows.isEmpty {
            status = .blocked
            reason = "Dock automation snapshot metadata is missing; launch the app with CODEX_DOCK_AUTOMATION_SNAPSHOTS=1 before running sim-ui-dump."
        } else if let expectedScreen = config.expectedScreenKind, expectedScreen != screenAfter {
            status = .fail
            reason = "Expected screen \(expectedScreen.rawValue), observed \(screenAfter.rawValue)."
        } else if let expectedThreadID = config.expectedThreadID,
                  sampleAfter.activeThreadID != expectedThreadID {
            status = .fail
            reason = "Expected thread \(expectedThreadID), observed \(sampleAfter.activeThreadID ?? "none")."
        }

        let dump = DisplayedUICurrentDump(
            status: status,
            reason: reason,
            capturedAt: sampleBefore.sampledAt,
            finishedAt: codexDockISO8601Now(),
            simulator: DisplayedUISimulatorMetadata(name: config.simulatorName, udid: config.simulatorUDID),
            app: DisplayedUIAppMetadata(
                bundleIdentifier: config.appBundleID,
                configuredBuildNumber: config.configuredBuildNumber
            ),
            launchMode: "activate",
            didRelaunch: false,
            stateBefore: stateBefore.codexDockName,
            stateAfter: stateAfter.codexDockName,
            screenBefore: screenBefore,
            screenAfter: screenAfter,
            activeThreadID: sampleAfter.activeThreadID,
            expectedScreen: config.expectedScreenKind,
            expectedThreadID: config.expectedThreadID,
            sampleBefore: sampleBefore,
            sampleAfter: sampleAfter,
            visibleElements: visibleElements,
            rawAccessibilityTree: status == .pass ? nil : app.debugDescription
        )
        try DisplayedUIArtifactWriter.writeDump(
            dump,
            jsonPath: config.jsonPath,
            markdownPath: config.markdownPath
        )

        guard status == .pass else {
            XCTFail(reason ?? "Simulator UI dump did not pass.")
            return
        }
    }

    private func writeBlockedDump(config: DisplayedUICurrentDumpConfig, reason: String) throws {
        let now = codexDockISO8601Now()
        let dump = DisplayedUICurrentDump(
            status: .blocked,
            reason: reason,
            capturedAt: now,
            finishedAt: now,
            simulator: DisplayedUISimulatorMetadata(name: config.simulatorName, udid: config.simulatorUDID),
            app: DisplayedUIAppMetadata(
                bundleIdentifier: config.appBundleID,
                configuredBuildNumber: config.configuredBuildNumber
            ),
            launchMode: "activate",
            didRelaunch: false,
            stateBefore: "unknown",
            stateAfter: "unknown",
            screenBefore: .unknown,
            screenAfter: .unknown,
            activeThreadID: nil,
            expectedScreen: config.expectedScreenKind,
            expectedThreadID: config.expectedThreadID,
            sampleBefore: nil,
            sampleAfter: nil,
            visibleElements: [],
            rawAccessibilityTree: nil
        )
        try DisplayedUIArtifactWriter.writeDump(
            dump,
            jsonPath: config.jsonPath,
            markdownPath: config.markdownPath
        )
    }
}

struct DisplayedUICurrentDumpConfig: Codable {
    var jsonPath: String
    var markdownPath: String
    var simulatorName: String
    var simulatorUDID: String
    var appBundleID: String
    var appDataContainer: String?
    var configuredBuildNumber: String?
    var expectedScreen: String?
    var expectedThreadID: String?
    var expiresAt: String

    static let path = "/tmp/codex-client/codex-dock-sim-ui-dump-config.json"
    static var requiresConfiguredRun: Bool {
        ProcessInfo.processInfo.environment["CODEX_DOCK_CURRENT_UI_DUMP_REQUIRE_CONFIG"] == "1"
    }

    var expectedScreenKind: DisplayedUIScreenKind? {
        guard let expectedScreen, !expectedScreen.isEmpty else {
            return nil
        }
        return DisplayedUIScreenKind(rawValue: expectedScreen)
    }

    static func load() throws -> DisplayedUICurrentDumpConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw error("missing config")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try JSONDecoder().decode(DisplayedUICurrentDumpConfig.self, from: data)
        guard let expiry = ISO8601DateFormatter().date(from: config.expiresAt), expiry > Date() else {
            throw error("expired config")
        }
        if let expectedScreen = config.expectedScreen, !expectedScreen.isEmpty,
           DisplayedUIScreenKind(rawValue: expectedScreen) == nil {
            throw error("invalid expectedScreen=\(expectedScreen)")
        }
        return config
    }

    private static func error(_ description: String) -> NSError {
        NSError(
            domain: "CodexDockCurrentUIDumpConfig",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    static func fallback() -> DisplayedUICurrentDumpConfig {
        DisplayedUICurrentDumpConfig(
            jsonPath: "/tmp/codex-client/codex-dock-sim-ui-dump.json",
            markdownPath: "/tmp/codex-client/codex-dock-sim-ui-dump.md",
            simulatorName: "unknown",
            simulatorUDID: "unknown",
            appBundleID: "com.aelaguiz.CodexDockApp",
            appDataContainer: nil,
            configuredBuildNumber: nil,
            expectedScreen: nil,
            expectedThreadID: nil,
            expiresAt: codexDockISO8601Now()
        )
    }
}
