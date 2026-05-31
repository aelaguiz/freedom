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
    // Local metadata decorates relay cards only. Pins, labels, and rails can be
    // local; title, status, activity, summary, freshness, and archive state must
    // come from the relay card stream.
    public var label: String? {
        didSet {
            label = Self.normalized(label)
        }
    }
    public var rail: DockRowRail?
    public var isPinned: Bool
    public var pinnedAt: Date?
    public var pinnedOrder: Int?

    public init(
        label: String? = nil,
        rail: DockRowRail? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        pinnedOrder: Int? = nil
    ) {
        self.label = Self.normalized(label)
        self.rail = rail
        self.isPinned = isPinned
        self.pinnedAt = isPinned ? pinnedAt : nil
        self.pinnedOrder = isPinned ? pinnedOrder : nil
    }

    public var isEmpty: Bool {
        label == nil
            && rail == nil
            && !isPinned
            && pinnedAt == nil
            && pinnedOrder == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case rail
        case isPinned
        case pinnedAt
        case pinnedOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            rail: try container.decodeIfPresent(DockRowRail.self, forKey: .rail),
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            pinnedAt: try container.decodeIfPresent(Date.self, forKey: .pinnedAt),
            pinnedOrder: try container.decodeIfPresent(Int.self, forKey: .pinnedOrder)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(rail, forKey: .rail)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encodeIfPresent(pinnedOrder, forKey: .pinnedOrder)
    }
}

public protocol LocalThreadMetadataStoring: Sendable {
    func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata]
    func save(
        _ metadata: LocalThreadMetadata?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata]
    func save(
        _ values: [LocalThreadMetadataKey: LocalThreadMetadata]
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
        let persisted = try await save(values)
        DockLog.persistence.debug("thread metadata persist finished host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) entries=\(persisted.count, privacy: .public)")
        return persisted
    }

    public func save(
        _ values: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        let persistedValues = values.filter { !$0.value.isEmpty }
        DockLog.persistence.debug("thread metadata batch persist started entries=\(persistedValues.count, privacy: .public)")
        try persist(persistedValues)
        cache = persistedValues
        DockLog.persistence.debug("thread metadata batch persist finished entries=\(persistedValues.count, privacy: .public)")
        return persistedValues
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
