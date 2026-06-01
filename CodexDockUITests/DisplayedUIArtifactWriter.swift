import Foundation

enum DisplayedUIArtifactWriter {
    static func writeSamples(_ samples: [DisplayedUISample], to path: String) throws {
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

    static func writeDump(_ dump: DisplayedUICurrentDump, jsonPath: String, markdownPath: String) throws {
        let jsonURL = URL(fileURLWithPath: jsonPath)
        let markdownURL = URL(fileURLWithPath: markdownPath)
        try FileManager.default.createDirectory(
            at: jsonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: markdownURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dump)
        try data.write(to: jsonURL, options: .atomic)
        try dump.markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
    }
}

struct DisplayedUICurrentDump: Codable {
    var schemaVersion: Int = 1
    var kind: String = "codex-dock-sim-ui-dump"
    var status: DisplayedUIArtifactStatus
    var reason: String?
    var capturedAt: String
    var finishedAt: String
    var simulator: DisplayedUISimulatorMetadata
    var app: DisplayedUIAppMetadata
    var launchMode: String
    var didRelaunch: Bool
    var stateBefore: String
    var stateAfter: String
    var screenBefore: DisplayedUIScreenKind
    var screenAfter: DisplayedUIScreenKind
    var activeThreadID: String?
    var expectedScreen: DisplayedUIScreenKind?
    var expectedThreadID: String?
    var sampleBefore: DisplayedUISample?
    var sampleAfter: DisplayedUISample?
    var visibleElements: [DisplayedUIVisibleElementSnapshot]
    var rawAccessibilityTree: String?

    var markdown: String {
        var lines: [String] = [
            "# Codex Dock Simulator UI Dump",
            "",
            "- status: \(status.rawValue)",
            "- reason: \(reason ?? "none")",
            "- simulator: \(simulator.name) (\(simulator.udid))",
            "- app: \(app.bundleIdentifier)",
            "- state: \(stateBefore) -> \(stateAfter)",
            "- launchMode: \(launchMode)",
            "- didRelaunch: \(didRelaunch)",
            "- screen: \(screenBefore.rawValue) -> \(screenAfter.rawValue)",
            "- activeThreadID: \(activeThreadID ?? "none")",
            "- visibleElements: \(visibleElements.count)",
        ]

        if let sampleAfter {
            lines.append("- dockRows: \(sampleAfter.dockRows.count)")
            lines.append("- hostSummaries: \(sampleAfter.hostSummaries.count)")
            lines.append("- detailMessages: \(sampleAfter.detail?.messageCardIDs.count ?? 0)")
            lines.append("- detailRequests: \(sampleAfter.detail?.requestCardIDs.count ?? 0)")
        }

        if let expectedScreen {
            lines.append("- expectedScreen: \(expectedScreen.rawValue)")
        }
        if let expectedThreadID {
            lines.append("- expectedThreadID: \(expectedThreadID)")
        }

        lines.append("")
        lines.append("JSON contains the full accessibility element list plus Dock and Thread rollups.")
        return lines.joined(separator: "\n") + "\n"
    }
}

struct DisplayedUISimulatorMetadata: Codable {
    var name: String
    var udid: String
}

struct DisplayedUIAppMetadata: Codable {
    var bundleIdentifier: String
    var configuredBuildNumber: String?
}
