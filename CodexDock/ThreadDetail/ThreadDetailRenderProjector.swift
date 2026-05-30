import Foundation

struct ThreadDetailRenderProjector: Sendable {
    func render(
        snapshot: ThreadDetailSnapshot,
        requestCards: [ServerRequestCard],
        options: ThreadDetailRenderOptions,
        revision: RenderRevision
    ) -> ThreadDetailRenderSnapshot {
        let filteredEvents = snapshot.events.filter { options.filter.includes($0) }
        let visibleEvents = Array(filteredEvents.prefix(options.visibleLimit))
        let requestCardIndex = ThreadDetailRequestCardIndex(requestCards: requestCards)
        let rows = visibleEvents.map { event in
            ThreadEventRenderRow(
                event: event,
                requestCard: requestCardIndex.card(for: event)
            )
        }

        return ThreadDetailRenderSnapshot(
            revision: revision,
            header: snapshot.header,
            liveState: snapshot.liveState,
            options: options,
            visibleWindow: ThreadVisibleWindow(
                startIndex: 0,
                rows: rows,
                totalMatchingCount: filteredEvents.count
            ),
            hasUnfilteredEvents: !snapshot.events.isEmpty
        )
    }
}

private struct ThreadDetailRequestCardIndex {
    private let byID: [String: ServerRequestCard]
    private let byStreamKey: [RequestCardStreamKey: ServerRequestCard]

    init(requestCards: [ServerRequestCard]) {
        var byID: [String: ServerRequestCard] = [:]
        var byStreamKey: [RequestCardStreamKey: ServerRequestCard] = [:]
        byID.reserveCapacity(requestCards.count)
        byStreamKey.reserveCapacity(requestCards.count)

        for card in requestCards {
            byID[card.id] = card
            if let key = RequestCardStreamKey(turnID: card.turnID, itemID: card.itemID) {
                byStreamKey[key] = card
            }
        }

        self.byID = byID
        self.byStreamKey = byStreamKey
    }

    func card(for event: ThreadEvent) -> ServerRequestCard? {
        guard event.kind == .request else {
            return nil
        }
        if let card = byID[event.id] {
            return card
        }
        guard let key = RequestCardStreamKey(turnID: event.turnID, itemID: event.itemID) else {
            return nil
        }
        return byStreamKey[key]
    }
}

private struct RequestCardStreamKey: Hashable {
    let turnID: String?
    let itemID: String?

    init?(turnID: String?, itemID: String?) {
        guard turnID != nil || itemID != nil else {
            return nil
        }
        self.turnID = turnID
        self.itemID = itemID
    }
}
