import Foundation

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

    func collect(from connection: any ThreadCardStreamConnection) async throws -> [DockThreadCardDTO] {
        try await withThrowingTaskGroup(of: [DockThreadCardDTO].self) { group in
            group.addTask {
                try await collectWithoutTimeout(from: connection, expectedView: expectedView)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DockRequestFailure.error("Timed out waiting for \(expectedView.rawValue) card stream to complete")
            }

            guard let cards = try await group.next() else {
                throw DockRequestFailure.error("Card stream ended before returning a snapshot")
            }
            group.cancelAll()
            return cards
        }
    }
}

private func collectWithoutTimeout(
    from connection: any ThreadCardStreamConnection,
    expectedView: ThreadCardStreamView
) async throws -> [DockThreadCardDTO] {
    var cardsByID: [String: DockThreadCardDTO] = [:]
    let snapshot = try await connection.subscribe()
    try apply(snapshot, expectedView: expectedView, cardsByID: &cardsByID)
    if isComplete(snapshot, visibleCount: cardsByID.count) {
        return sortedCards(cardsByID)
    }

    for try await update in connection.updates() {
        try apply(update, expectedView: expectedView, cardsByID: &cardsByID)
        if isComplete(update, visibleCount: cardsByID.count) {
            return sortedCards(cardsByID)
        }
    }

    throw DockRequestFailure.error("Card stream closed before \(expectedView.rawValue) snapshot completed")
}

private func apply(
    _ update: ThreadCardStreamUpdateDTO,
    expectedView: ThreadCardStreamView,
    cardsByID: inout [String: DockThreadCardDTO]
) throws {
    guard update.schemaVersion == CodexDockConstants.Dock.streamSchemaVersion,
          update.view == expectedView else {
        throw DockRequestFailure.error("Unexpected \(expectedView.rawValue) card stream contract")
    }

    switch update.kind {
    case .snapshot:
        cardsByID = Dictionary(uniqueKeysWithValues: (update.cards ?? []).map { ($0.id, $0) })
    case .delta:
        for card in update.upsertCards ?? [] {
            cardsByID[card.id] = card
        }
        for cardID in update.deleteCardIDs ?? [] {
            cardsByID.removeValue(forKey: cardID)
        }
    case .heartbeat:
        break
    }
}

private func isComplete(_ update: ThreadCardStreamUpdateDTO, visibleCount: Int) -> Bool {
    if update.complete == true {
        return true
    }
    guard update.window?.nextOffset == nil,
          let totalRows = update.totalRows else {
        return false
    }
    return visibleCount >= totalRows
}

private func sortedCards(_ cardsByID: [String: DockThreadCardDTO]) -> [DockThreadCardDTO] {
    cardsByID.values.sorted { lhs, rhs in
        if lhs.orderKey != rhs.orderKey {
            return lhs.orderKey < rhs.orderKey
        }
        return lhs.id < rhs.id
    }
}
