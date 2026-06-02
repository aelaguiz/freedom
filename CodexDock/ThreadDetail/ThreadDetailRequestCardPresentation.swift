import Foundation

struct ThreadDetailRequestCardPresentation: Equatable, Sendable {
    private var localStateByProjectionID: [String: ThreadDetailRequestCardLocalState] = [:]

    func cards(from events: [ThreadEvent]) -> [ServerRequestCard] {
        events.compactMap(card(for:))
    }

    func card(for event: ThreadEvent) -> ServerRequestCard? {
        guard var card = ServerRequestCard.make(from: event) else {
            return nil
        }
        guard let localState = localStateByProjectionID[event.id] else {
            return card
        }
        card.inputDraft = localState.inputDraft
        card.status = mergedStatus(
            serverStatus: card.status,
            localStatus: localState.status
        )
        return card
    }

    func card(for projectionID: String, in events: [ThreadEvent]) -> ServerRequestCard? {
        guard let event = events.first(where: { $0.id == projectionID && $0.request != nil }) else {
            return nil
        }
        return card(for: event)
    }

    mutating func updateInput(
        projectionID: String,
        draft: String,
        in events: [ThreadEvent]
    ) -> Bool {
        guard card(for: projectionID, in: events) != nil else {
            return false
        }
        var localState = localStateByProjectionID[projectionID] ?? ThreadDetailRequestCardLocalState()
        localState.inputDraft = draft
        if case .failed = localState.status {
            localState.status = .pending
        }
        localStateByProjectionID[projectionID] = localState
        return true
    }

    mutating func setStatus(
        projectionID: String,
        status: ServerRequestCardStatus,
        in events: [ThreadEvent]
    ) -> Bool {
        guard card(for: projectionID, in: events) != nil else {
            return false
        }
        var localState = localStateByProjectionID[projectionID] ?? ThreadDetailRequestCardLocalState()
        localState.status = status
        localStateByProjectionID[projectionID] = localState
        return true
    }

    mutating func prune(to events: [ThreadEvent]) {
        let activeRequestIDs = Set(events.compactMap { event in
            event.request == nil ? nil : event.id
        })
        localStateByProjectionID = localStateByProjectionID.filter { activeRequestIDs.contains($0.key) }
    }

    private func mergedStatus(
        serverStatus: ServerRequestCardStatus,
        localStatus: ServerRequestCardStatus?
    ) -> ServerRequestCardStatus {
        guard let localStatus else {
            return serverStatus
        }
        switch localStatus {
        case .responding, .failed:
            return localStatus
        case .resolved:
            return serverStatus == .pending ? localStatus : serverStatus
        case .pending:
            return serverStatus
        }
    }
}

private struct ThreadDetailRequestCardLocalState: Equatable, Sendable {
    var inputDraft: String = ""
    var status: ServerRequestCardStatus?
}
