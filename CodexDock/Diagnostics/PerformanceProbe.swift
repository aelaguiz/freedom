import Foundation

#if os(iOS)
import QuartzCore
import UIKit
#endif

enum PerformanceProbe {
    struct Configuration: Sendable {
        let enabled: Bool
        let rowAppearSampleLimit: Int
        let rowDisappearSampleLimit: Int
        let scrollSampleLimit: Int
        let scrollDeltaThresholdPoints: Int
        let frameHitchWarningMilliseconds: Int
    }

    private struct FileConfiguration: Decodable {
        let enabled: Bool?
        let rowAppearSampleLimit: Int?
        let rowDisappearSampleLimit: Int?
        let scrollSampleLimit: Int?
        let scrollDeltaThresholdPoints: Int?
        let frameHitchWarningMilliseconds: Int?
    }

    static let configuration = loadConfiguration()

    static var isEnabled: Bool {
        configuration.enabled
    }

    static func event(_ name: String, fields: [String: String] = [:]) {
        guard isEnabled else {
            return
        }
        DockLog.metrics.notice("perf event=\(name, privacy: .public) \(formatted(fields), privacy: .public)")
    }

    static func measure<T>(
        _ name: String,
        fields: [String: String] = [:],
        _ operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try operation()
        }

        let startedAt = Date()
        do {
            let value = try operation()
            event(
                name,
                fields: fields.merging(["duration_ms": "\(milliseconds(since: startedAt))"]) { _, new in new }
            )
            return value
        } catch {
            event(
                name,
                fields: fields.merging([
                    "duration_ms": "\(milliseconds(since: startedAt))",
                    "error": "true",
                ]) { _, new in new }
            )
            throw error
        }
    }

    static func milliseconds(since start: Date, now: Date = Date()) -> Int {
        DockLog.milliseconds(since: start, now: now)
    }

    @MainActor
    static func dockViewLoadedRevision(
        revision: RenderRevision,
        snapshot: DockSnapshot,
        projection: DockCardProjection,
        options: DockProjectionOptions
    ) {
        guard isEnabled else {
            return
        }
        if currentDockRevision != revision.rawValue {
            currentDockRevision = revision.rawValue
            rowAppearSampleCount = 0
            rowDisappearSampleCount = 0
        }
        currentDockRowCount = snapshot.rowCount
        currentDockVisibleRowCount = projection.rows.count
        event(
            "dock.view.loaded_revision",
            fields: [
                "revision": "\(revision.rawValue)",
                "hosts": "\(snapshot.hosts.count)",
                "rows": "\(snapshot.rows.count)",
                "visible_rows": "\(projection.rows.count)",
                "pinned_rows": "\(projection.pinnedRows.count)",
                "groups": "\(projection.groups.count)",
                "lens": options.lens.rawValue,
                "search": options.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                "filters": "\(options.filters.activeFilterCount)",
                "partial": "\(snapshot.isPartial)",
            ]
        )
    }

    @MainActor
    static func dockRowAppeared(_ row: DockRowViewModel) {
        guard isEnabled,
              rowAppearSampleCount < configuration.rowAppearSampleLimit else {
            return
        }
        rowAppearSampleCount += 1
        event(
            "dock.row.appear",
            fields: [
                "sample": "\(rowAppearSampleCount)",
                "revision": currentDockRevision.map(String.init) ?? "none",
                "host_id": row.hostID,
                "source_host_id": row.sourceHostID ?? "none",
                "status": row.status.rawValue,
                "origin": row.origin.automationKind,
                "relationship": row.relationship.rawValue,
                "pinned": "\(row.isPinned)",
            ]
        )
    }

    @MainActor
    static func dockRowDisappeared(_ row: DockRowViewModel) {
        guard isEnabled,
              rowDisappearSampleCount < configuration.rowDisappearSampleLimit else {
            return
        }
        rowDisappearSampleCount += 1
        event(
            "dock.row.disappear",
            fields: [
                "sample": "\(rowDisappearSampleCount)",
                "revision": currentDockRevision.map(String.init) ?? "none",
                "host_id": row.hostID,
                "source_host_id": row.sourceHostID ?? "none",
                "status": row.status.rawValue,
                "origin": row.origin.automationKind,
                "relationship": row.relationship.rawValue,
                "pinned": "\(row.isPinned)",
            ]
        )
    }

    @MainActor
    static func dockScrollObserverAttached(
        attempt: Int,
        offsetY: Double,
        contentHeight: Double,
        boundsHeight: Double,
        adjustedTopInset: Double,
        adjustedBottomInset: Double
    ) {
        guard isEnabled else {
            return
        }
        event(
            "dock.scroll.attached",
            fields: [
                "attempt": "\(attempt)",
                "offset_y": "\(Int(offsetY.rounded()))",
                "content_height": "\(Int(contentHeight.rounded()))",
                "bounds_height": "\(Int(boundsHeight.rounded()))",
                "adjusted_top_inset": "\(Int(adjustedTopInset.rounded()))",
                "adjusted_bottom_inset": "\(Int(adjustedBottomInset.rounded()))",
            ]
        )
    }

    @MainActor
    static func dockScrollOffsetChanged(offsetY: Double) {
        dockScrollOffsetChanged(
            offsetY: offsetY,
            contentHeight: nil,
            boundsHeight: nil,
            source: "direct",
            revision: currentDockRevision.map { RenderRevision(rawValue: $0) },
            rowCount: currentDockRowCount,
            visibleRowCount: currentDockVisibleRowCount
        )
    }

    @MainActor
    static func dockSwiftUIScrollOffsetChanged(offsetY: Double) {
        dockScrollOffsetChanged(
            offsetY: offsetY,
            contentHeight: nil,
            boundsHeight: nil,
            source: "swiftui_geometry",
            revision: currentDockRevision.map { RenderRevision(rawValue: $0) },
            rowCount: currentDockRowCount,
            visibleRowCount: currentDockVisibleRowCount
        )
    }

    @MainActor
    static func dockScrollOffsetChanged(
        offsetY: Double,
        contentHeight: Double,
        boundsHeight: Double
    ) {
        dockScrollOffsetChanged(
            offsetY: offsetY,
            contentHeight: contentHeight,
            boundsHeight: boundsHeight,
            source: "uiscrollview",
            revision: currentDockRevision.map { RenderRevision(rawValue: $0) },
            rowCount: currentDockRowCount,
            visibleRowCount: currentDockVisibleRowCount
        )
    }

    @MainActor
    static func dockScrollOffsetChanged(
        offsetY: Double,
        contentHeight: Double?,
        boundsHeight: Double?,
        source: String,
        revision: RenderRevision?,
        rowCount: Int,
        visibleRowCount: Int
    ) {
        guard isEnabled,
              scrollSampleCount < configuration.scrollSampleLimit else {
            return
        }

        let deltaY: Double
        if let lastScrollOffsetY = lastScrollOffsetYBySource[source] {
            deltaY = offsetY - lastScrollOffsetY
            guard abs(deltaY) >= Double(configuration.scrollDeltaThresholdPoints) else {
                return
            }
        } else {
            deltaY = 0
        }

        lastScrollOffsetYBySource[source] = offsetY
        scrollSampleCount += 1
        var fields = [
            "sample": "\(scrollSampleCount)",
            "source": source,
            "revision": revision.map { "\($0.rawValue)" } ?? "none",
            "offset_y": "\(Int(offsetY.rounded()))",
            "delta_y": "\(Int(deltaY.rounded()))",
            "rows": "\(rowCount)",
            "visible_rows": "\(visibleRowCount)",
        ]
        if let contentHeight {
            fields["content_height"] = "\(Int(contentHeight.rounded()))"
        }
        if let boundsHeight {
            fields["bounds_height"] = "\(Int(boundsHeight.rounded()))"
        }
        event(
            "dock.scroll.offset",
            fields: fields
        )
    }

    @MainActor
    static func dockAccessibilityValueBuilt(
        revision: RenderRevision?,
        rowCount: Int,
        visibleRowCount: Int,
        encodedLength: Int,
        durationMilliseconds: Int
    ) {
        guard isEnabled else {
            return
        }
        event(
            "dock.accessibility_value.built",
            fields: [
                "revision": revision.map { "\($0.rawValue)" } ?? "none",
                "rows": "\(rowCount)",
                "visible_rows": "\(visibleRowCount)",
                "encoded_length": "\(encodedLength)",
                "duration_ms": "\(durationMilliseconds)",
            ]
        )
    }

    static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("CodexDock", isDirectory: true)
            .appendingPathComponent("performance-profiling.json")
    }

    @MainActor private static var currentDockRevision: UInt64?
    @MainActor private static var rowAppearSampleCount = 0
    @MainActor private static var rowDisappearSampleCount = 0
    @MainActor private static var scrollSampleCount = 0
    @MainActor private static var lastScrollOffsetYBySource: [String: Double] = [:]
    @MainActor private static var currentDockRowCount = 0
    @MainActor private static var currentDockVisibleRowCount = 0

    private static func loadConfiguration() -> Configuration {
        let environment = ProcessInfo.processInfo.environment
        let environmentEnabled = boolValue(environment["CODEX_DOCK_PERFORMANCE_PROFILING"])
            ?? boolValue(environment["CODEX_DOCK_UI_PROFILING"])

        let fileConfiguration = loadFileConfiguration()
        let enabled = environmentEnabled ?? fileConfiguration.enabled ?? false
        return Configuration(
            enabled: enabled,
            rowAppearSampleLimit: max(0, fileConfiguration.rowAppearSampleLimit ?? 80),
            rowDisappearSampleLimit: max(0, fileConfiguration.rowDisappearSampleLimit ?? 80),
            scrollSampleLimit: max(0, fileConfiguration.scrollSampleLimit ?? 160),
            scrollDeltaThresholdPoints: max(1, fileConfiguration.scrollDeltaThresholdPoints ?? 16),
            frameHitchWarningMilliseconds: max(16, fileConfiguration.frameHitchWarningMilliseconds ?? 34)
        )
    }

    private static func loadFileConfiguration() -> FileConfiguration {
        let fileURL = defaultFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let configuration = try? JSONDecoder().decode(FileConfiguration.self, from: data) else {
            return FileConfiguration(
                enabled: nil,
                rowAppearSampleLimit: nil,
                rowDisappearSampleLimit: nil,
                scrollSampleLimit: nil,
                scrollDeltaThresholdPoints: nil,
                frameHitchWarningMilliseconds: nil
            )
        }
        return configuration
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func formatted(_ fields: [String: String]) -> String {
        guard !fields.isEmpty else {
            return "fields=none"
        }
        return fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(DockLog.redacted($0.value, maxLength: 120))" }
            .joined(separator: " ")
    }
}

#if os(iOS)
@MainActor
final class PerformanceFrameMonitor: NSObject {
    static let shared = PerformanceFrameMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var hitchCount = 0

    func startIfNeeded() {
        guard PerformanceProbe.isEnabled,
              displayLink == nil else {
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        PerformanceProbe.event(
            "frame_monitor.started",
            fields: [
                "hitch_warning_ms": "\(PerformanceProbe.configuration.frameHitchWarningMilliseconds)",
            ]
        )
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer {
            lastTimestamp = link.timestamp
        }
        guard let lastTimestamp else {
            return
        }
        let durationMilliseconds = max(0, Int(((link.timestamp - lastTimestamp) * 1_000).rounded()))
        guard durationMilliseconds >= PerformanceProbe.configuration.frameHitchWarningMilliseconds else {
            return
        }
        hitchCount += 1
        let targetMilliseconds = max(0, Int(((link.targetTimestamp - link.timestamp) * 1_000).rounded()))
        PerformanceProbe.event(
            "frame.hitch",
            fields: [
                "duration_ms": "\(durationMilliseconds)",
                "target_ms": "\(targetMilliseconds)",
                "hitch_count": "\(hitchCount)",
            ]
        )
    }
}
#endif
