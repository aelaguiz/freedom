import Foundation

enum PinnedMetadataOrdering {
    static func normalized(
        _ values: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        var normalized = values
        for (index, key) in orderedKeys(in: values).enumerated() {
            guard var metadata = normalized[key], metadata.isPinned else {
                continue
            }
            metadata.pinnedOrder = index
            normalized[key] = metadata
        }
        return normalized
    }

    static func orderedKeys(
        in values: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) -> [LocalThreadMetadataKey] {
        values
            .filter { $0.value.isPinned }
            .sorted(by: precedes)
            .map(\.key)
    }

    static func nextOrder(
        in values: [LocalThreadMetadataKey: LocalThreadMetadata],
        excluding excludedKey: LocalThreadMetadataKey
    ) -> Int {
        let maxOrder = values
            .filter { $0.key != excludedKey && $0.value.isPinned }
            .compactMap(\.value.pinnedOrder)
            .max()
        return (maxOrder ?? -1) + 1
    }

    static func uniqueKeys(_ keys: [LocalThreadMetadataKey]) -> [LocalThreadMetadataKey] {
        var seen = Set<LocalThreadMetadataKey>()
        var unique: [LocalThreadMetadataKey] = []
        for key in keys where !seen.contains(key) {
            seen.insert(key)
            unique.append(key)
        }
        return unique
    }

    private static func precedes(
        _ lhs: (key: LocalThreadMetadataKey, value: LocalThreadMetadata),
        _ rhs: (key: LocalThreadMetadataKey, value: LocalThreadMetadata)
    ) -> Bool {
        if let lhsOrder = lhs.value.pinnedOrder,
           let rhsOrder = rhs.value.pinnedOrder,
           lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        if lhs.value.pinnedOrder != nil {
            return true
        }
        if rhs.value.pinnedOrder != nil {
            return false
        }

        let lhsPinnedAt = lhs.value.pinnedAt ?? Date.distantPast
        let rhsPinnedAt = rhs.value.pinnedAt ?? Date.distantPast
        if lhsPinnedAt != rhsPinnedAt {
            return lhsPinnedAt < rhsPinnedAt
        }

        return keyPrecedes(lhs.key, rhs.key)
    }

    private static func keyPrecedes(_ lhs: LocalThreadMetadataKey, _ rhs: LocalThreadMetadataKey) -> Bool {
        [
            lhs.hostID,
            lhs.backendSessionID,
            lhs.threadID,
        ].joined(separator: "\u{1f}") < [
            rhs.hostID,
            rhs.backendSessionID,
            rhs.threadID,
        ].joined(separator: "\u{1f}")
    }
}
