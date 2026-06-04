import Foundation

struct DockAutomationSnapshotMetadata: Equatable, Sendable {
    let revision: RenderRevision
    let relativePath: String
}

struct DockAutomationSnapshotStore: Sendable {
    static let relativeDirectory = "CodexDock/DockAutomationSnapshots"

    private let directoryURL: URL
    private let relativeDirectory: String
    private let now: @Sendable () -> Date
    private let retainedSnapshotCount: Int

    init(
        directoryURL: URL,
        relativeDirectory: String = Self.relativeDirectory,
        retainedSnapshotCount: Int = 5,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.relativeDirectory = relativeDirectory
        self.retainedSnapshotCount = retainedSnapshotCount
        self.now = now
    }

    func write(
        renderSnapshot: DockRenderSnapshot,
        options: DockProjectionOptions
    ) throws -> DockAutomationSnapshotMetadata {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let revision = renderSnapshot.revision.rawValue
        let fileName = "dock-automation-snapshot-\(revision).json"
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        let snapshot = DockAutomationSnapshot(
            schemaVersion: 1,
            revision: revision,
            createdAt: Self.timestamp(now()),
            rows: renderSnapshot.projection.automationRows.enumerated().map { index, row in
                DockAutomationSnapshotRow(
                    identifier: AutomationID.Dock.row(hostID: row.hostID, threadID: row.threadID).rawValue,
                    value: row.automationValue,
                    label: "",
                    frame: DockAutomationSnapshotFrame(
                        minX: 0,
                        minY: Double(index),
                        width: 1,
                        height: 1
                    )
                )
            },
            visibleRows: renderSnapshot.projection.automationRows.count,
            pinned: renderSnapshot.projection.pinnedRows.count,
            lens: renderSnapshot.projection.lens.rawValue,
            search: !options.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            filters: options.filters.activeFilterCount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        // UI tests read the root value only after this atomic write succeeds.
        // Do not advertise a revision whose JSON row oracle is not on disk.
        try data.write(to: fileURL, options: [.atomic])
        try pruneSnapshots(fileManager: fileManager)

        return DockAutomationSnapshotMetadata(
            revision: renderSnapshot.revision,
            relativePath: "\(relativeDirectory)/\(fileName)"
        )
    }

    private func pruneSnapshots(fileManager: FileManager) throws {
        guard retainedSnapshotCount > 0 else {
            return
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        let snapshotURLs = urls.compactMap { url -> (URL, UInt64)? in
            guard let revision = Self.revision(from: url.lastPathComponent) else {
                return nil
            }
            return (url, revision)
        }
        let oldSnapshots = snapshotURLs
            .sorted { $0.1 > $1.1 }
            .dropFirst(retainedSnapshotCount)
        for (url, _) in oldSnapshots {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func revision(from fileName: String) -> UInt64? {
        let prefix = "dock-automation-snapshot-"
        let suffix = ".json"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else {
            return nil
        }
        let start = fileName.index(fileName.startIndex, offsetBy: prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -suffix.count)
        return UInt64(fileName[start..<end])
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum DockAutomationSnapshotConfiguration {
    static let enabledEnvironmentKey = "CODEX_DOCK_AUTOMATION_SNAPSHOTS"

    static func makeIfEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DockAutomationSnapshotStore? {
        guard environment[enabledEnvironmentKey] == "1" else {
            return nil
        }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = applicationSupport
            .appendingPathComponent(DockAutomationSnapshotStore.relativeDirectory, isDirectory: true)
        return DockAutomationSnapshotStore(directoryURL: directory)
    }
}

private struct DockAutomationSnapshot: Codable {
    let schemaVersion: Int
    let revision: UInt64
    let createdAt: String
    let rows: [DockAutomationSnapshotRow]
    let visibleRows: Int
    let pinned: Int
    let lens: String
    let search: Bool
    let filters: Int
}

private struct DockAutomationSnapshotRow: Codable {
    let identifier: String
    let value: String
    let label: String
    let frame: DockAutomationSnapshotFrame
}

private struct DockAutomationSnapshotFrame: Codable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}
