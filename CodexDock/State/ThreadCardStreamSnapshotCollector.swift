import Foundation

struct ThreadCardSnapshotCollection: Equatable, Sendable {
    let hosts: [DockStreamHostDTO]
    let cards: [DockThreadCardDTO]
}

struct ThreadCardStreamSnapshotCollector: Sendable {
    let expectedView: ThreadCardStreamView
    let timeout: Duration

    init(
        expectedView: ThreadCardStreamView,
        timeout: Duration = CodexDockConstants.AppServer.defaultRequestTimeout
    ) {
        self.expectedView = expectedView
        self.timeout = timeout
    }

    func collect(from connection: any ThreadCardStreamConnection) async throws -> ThreadCardSnapshotCollection {
        try await withThrowingTaskGroup(of: ThreadCardSnapshotCollection.self) { group in
            group.addTask {
                try await collectWithoutTimeout(from: connection, expectedView: expectedView)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DockRequestFailure.error("Timed out waiting for \(expectedView.rawValue) card stream to complete")
            }

            guard let collection = try await group.next() else {
                throw DockRequestFailure.error("Card stream ended before returning a snapshot")
            }
            group.cancelAll()
            return collection
        }
    }
}

private func collectWithoutTimeout(
    from connection: any ThreadCardStreamConnection,
    expectedView: ThreadCardStreamView
) async throws -> ThreadCardSnapshotCollection {
    var hostsByID: [String: DockStreamHostDTO] = [:]
    var cardsByID: [String: DockThreadCardDTO] = [:]
    let snapshot = try await connection.subscribe()
    try apply(
        snapshot,
        expectedView: expectedView,
        hostsByID: &hostsByID,
        cardsByID: &cardsByID
    )
    if isComplete(snapshot) {
        return ThreadCardSnapshotCollection(hosts: sortedHosts(hostsByID), cards: sortedCards(cardsByID))
    }

    for try await update in connection.updates() {
        try apply(
            update,
            expectedView: expectedView,
            hostsByID: &hostsByID,
            cardsByID: &cardsByID
        )
        if isComplete(update) {
            return ThreadCardSnapshotCollection(hosts: sortedHosts(hostsByID), cards: sortedCards(cardsByID))
        }
    }

    throw DockRequestFailure.error("Card stream closed before \(expectedView.rawValue) snapshot completed")
}

private func apply(
    _ update: ThreadCardStreamUpdateDTO,
    expectedView: ThreadCardStreamView,
    hostsByID: inout [String: DockStreamHostDTO],
    cardsByID: inout [String: DockThreadCardDTO]
) throws {
    guard update.schemaVersion == CodexDockConstants.Dock.streamSchemaVersion,
          update.view == expectedView else {
        throw DockRequestFailure.error("Unexpected \(expectedView.rawValue) card stream contract")
    }

    switch update.kind {
    case .snapshot:
        hostsByID = Dictionary(uniqueKeysWithValues: (update.hosts ?? []).map { ($0.id, $0) })
        cardsByID = Dictionary(uniqueKeysWithValues: (update.cards ?? [])
            .filter(\.isAppFacingHumanThreadCard)
            .map { ($0.id, $0) })
    case .delta:
        for host in update.upsertHosts ?? [] {
            hostsByID[host.id] = host
        }
        for card in (update.upsertCards ?? []).filter(\.isAppFacingHumanThreadCard) {
            cardsByID[card.id] = card
        }
        for cardID in update.deleteCardIDs ?? [] {
            cardsByID.removeValue(forKey: cardID)
        }
    case .heartbeat:
        break
    }
}

private func sortedHosts(_ hostsByID: [String: DockStreamHostDTO]) -> [DockStreamHostDTO] {
    hostsByID.values.sorted { lhs, rhs in
        lhs.id < rhs.id
    }
}

private func isComplete(_ update: ThreadCardStreamUpdateDTO) -> Bool {
    if update.complete == true {
        return true
    }
    guard update.window?.nextOffset == nil,
          update.totalRows != nil else {
        return false
    }
    // Bad relay payloads may count rejected non-human rows in totalRows. A final window still completes after filtering.
    return true
}

private func sortedCards(_ cardsByID: [String: DockThreadCardDTO]) -> [DockThreadCardDTO] {
    cardsByID.values.sorted { lhs, rhs in
        if lhs.orderKey != rhs.orderKey {
            return lhs.orderKey < rhs.orderKey
        }
        return lhs.id < rhs.id
    }
}
