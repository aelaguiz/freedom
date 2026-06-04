import Foundation

struct ThreadDetailRenderProjector: Sendable {
    func render(
        snapshot: ThreadDetailSnapshot,
        requestCardPresentation: ThreadDetailRequestCardPresentation = ThreadDetailRequestCardPresentation(),
        options: ThreadDetailRenderOptions,
        revision: RenderRevision
    ) -> ThreadDetailRenderSnapshot {
        let canonicalClientIDs = Set(snapshot.events.compactMap(\.clientID))
        let pendingEvents = snapshot.pendingOutboundMessages
            .filter { !canonicalClientIDs.contains($0.id.rawValue) }
            .map { $0.event(sourceHostID: snapshot.header.hostID, threadID: snapshot.header.threadID) }
        let allEvents = ThreadEventDisplayOrder.newestFirst(snapshot.events + pendingEvents)
        let filteredEvents = allEvents.filter { options.filter.includes($0) }
        let visibleEvents = Array(filteredEvents.prefix(options.visibleLimit))
        // Request cards are a decoration on canonical projection rows. Do not
        // pass or render a second card list that can drift from `snapshot.events`.
        let rows = visibleEvents.map { event in
            ThreadEventRenderRow(
                event: event,
                requestCard: requestCardPresentation.card(for: event)
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
            hasUnfilteredEvents: !allEvents.isEmpty
        )
    }
}
