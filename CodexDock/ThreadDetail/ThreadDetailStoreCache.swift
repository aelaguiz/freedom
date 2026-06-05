import Combine
import Foundation

@MainActor
final class ThreadDetailStoreCache: ObservableObject {
    private struct Entry {
        let store: ThreadDetailStore
        var accessOrdinal: Int
    }

    private let capacity: Int
    private var entries: [HostScopedThreadID: Entry] = [:]
    private var nextAccessOrdinal = 0

    init(capacity: Int = CodexDockConstants.ThreadDetail.retainedStoreCapacity) {
        self.capacity = max(1, capacity)
    }

    deinit {
        MainActor.assumeIsolated {
            closeAll()
        }
    }

    var count: Int {
        entries.count
    }

    func store(
        for row: DockRowViewModel,
        make: () -> ThreadDetailStore
    ) -> ThreadDetailStore {
        let key = row.threadIdentity
        if var entry = entries[key] {
            entry.accessOrdinal = nextAccess()
            entries[key] = entry
            entry.store.observeDockRowUpdate(row)
            entry.store.reattachView()
            return entry.store
        }

        let store = make()
        entries[key] = Entry(store: store, accessOrdinal: nextAccess())
        evictIfNeeded(protectedKey: key)
        return store
    }

    func closeAll() {
        let stores = entries.values.map(\.store)
        entries.removeAll(keepingCapacity: false)
        stores.forEach { $0.close() }
    }

    private func nextAccess() -> Int {
        defer {
            nextAccessOrdinal += 1
        }
        return nextAccessOrdinal
    }

    private func evictIfNeeded(protectedKey: HostScopedThreadID) {
        while entries.count > capacity {
            guard let keyToEvict = entries
                .filter({ $0.key != protectedKey })
                .min(by: { $0.value.accessOrdinal < $1.value.accessOrdinal })?
                .key else {
                return
            }
            let store = entries.removeValue(forKey: keyToEvict)?.store
            store?.close()
        }
    }
}
