import Foundation

public struct LocalThreadMetadataKey: Codable, Equatable, Hashable, Sendable {
    public let hostID: String
    public let backendSessionID: String
    public let threadID: String

    public init(hostID: String, backendSessionID: String, threadID: String) {
        self.hostID = hostID
        self.backendSessionID = backendSessionID
        self.threadID = threadID
    }
}

public struct LocalThreadMetadata: Codable, Equatable, Sendable {
    public var label: String?
    public var rail: DockRowRail?

    public init(label: String? = nil, rail: DockRowRail? = nil) {
        self.label = Self.normalized(label)
        self.rail = rail
    }

    public var isEmpty: Bool {
        label == nil && rail == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }
}

public protocol LocalThreadMetadataStoring: Sendable {
    func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata]
    func save(
        _ metadata: LocalThreadMetadata?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata]
}

public actor FileLocalThreadMetadataStore: LocalThreadMetadataStoring {
    private struct Entry: Codable {
        let key: LocalThreadMetadataKey
        let metadata: LocalThreadMetadata
    }

    private let fileURL: URL
    private var cache: [LocalThreadMetadataKey: LocalThreadMetadata]?

    public init(fileURL: URL = FileLocalThreadMetadataStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        if let cache {
            DockLog.persistence.debug("thread metadata load cache hit entries=\(cache.count, privacy: .public)")
            return cache
        }

        let loaded: [LocalThreadMetadataKey: LocalThreadMetadata]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            DockLog.persistence.debug("thread metadata load started path=\(self.fileURL.path, privacy: .public)")
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            loaded = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.metadata) })
        } else {
            loaded = [:]
        }
        cache = loaded
        DockLog.persistence.debug("thread metadata load finished entries=\(loaded.count, privacy: .public)")
        return loaded
    }

    public func save(
        _ metadata: LocalThreadMetadata?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        var values = try await load()
        if let metadata, !metadata.isEmpty {
            values[key] = metadata
        } else {
            values.removeValue(forKey: key)
        }
        DockLog.persistence.debug("thread metadata persist started host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) entries=\(values.count, privacy: .public)")
        try persist(values)
        cache = values
        DockLog.persistence.debug("thread metadata persist finished host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) entries=\(values.count, privacy: .public)")
        return values
    }

    private func persist(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let entries = values
            .map { Entry(key: $0.key, metadata: $0.value) }
            .sorted {
                [$0.key.hostID, $0.key.backendSessionID, $0.key.threadID].joined(separator: "\u{1f}")
                    < [$1.key.hostID, $1.key.backendSessionID, $1.key.threadID].joined(separator: "\u{1f}")
            }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("CodexDock", isDirectory: true)
            .appendingPathComponent("thread-metadata.json")
    }
}
