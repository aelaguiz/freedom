import Foundation

actor LocalMetadataEngine {
    private let store: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private var values: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(
        store: any LocalThreadMetadataStoring,
        initialValues: [LocalThreadMetadataKey: LocalThreadMetadata] = [:],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.values = initialValues
        self.now = now
    }

    func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        values = try await store.load()
        return values
    }

    func replace(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) {
        self.values = values
    }

    func setLabel(
        _ label: String?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        var metadata = values[key] ?? LocalThreadMetadata()
        metadata.label = label
        return try await save(metadata: metadata, for: key)
    }

    func setRail(
        _ rail: DockRowRail?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        var metadata = values[key] ?? LocalThreadMetadata()
        metadata.rail = rail
        return try await save(metadata: metadata, for: key)
    }

    func setPinned(
        _ isPinned: Bool,
        for row: DockRowViewModel
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        let key = row.metadataKey
        var nextValues = PinnedMetadataOrdering.normalized(values)
        var metadata = nextValues[key] ?? LocalThreadMetadata()
        if isPinned {
            let wasPinned = metadata.isPinned
            metadata.isPinned = true
            metadata.pinnedAt = metadata.pinnedAt ?? now()
            if !wasPinned || metadata.pinnedOrder == nil {
                metadata.pinnedOrder = PinnedMetadataOrdering.nextOrder(in: nextValues, excluding: key)
            }
            metadata.lastKnownPinnedDisplay = LocalPinnedDisplaySnapshot(row: row)
        } else {
            metadata.isPinned = false
            metadata.pinnedAt = nil
            metadata.pinnedOrder = nil
            metadata.lastKnownPinnedDisplay = nil
        }
        nextValues[key] = metadata
        return try await save(metadataValues: PinnedMetadataOrdering.normalized(nextValues))
    }

    func reorderPinnedRows(
        _ visibleRowsInNewOrder: [DockRowViewModel]
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        var nextValues = PinnedMetadataOrdering.normalized(values)
        let visibleKeys = PinnedMetadataOrdering.uniqueKeys(
            visibleRowsInNewOrder.map(\.metadataKey).filter { nextValues[$0]?.isPinned == true }
        )
        guard visibleKeys.count > 1 else {
            return nextValues
        }

        let visibleKeySet = Set(visibleKeys)
        let orderedPinnedKeys = PinnedMetadataOrdering.orderedKeys(in: nextValues)
        var reorderedVisibleKeys = visibleKeys.makeIterator()
        let mergedKeys = orderedPinnedKeys.compactMap { key in
            if visibleKeySet.contains(key) {
                return reorderedVisibleKeys.next()
            }
            return key
        }

        for (index, key) in mergedKeys.enumerated() {
            guard var metadata = nextValues[key], metadata.isPinned else {
                continue
            }
            metadata.pinnedOrder = index
            nextValues[key] = metadata
        }
        return try await save(metadataValues: nextValues)
    }

    private func save(
        metadata: LocalThreadMetadata,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        values = try await store.save(metadata.isEmpty ? nil : metadata, for: key)
        return values
    }

    private func save(
        metadataValues nextValues: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        let persistedValues = nextValues.filter { !$0.value.isEmpty }
        guard values != persistedValues else {
            return values
        }
        values = try await store.save(persistedValues)
        return values
    }
}
