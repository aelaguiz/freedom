import Foundation

struct ThreadDetailRenderProjector: Sendable {
    func render(
        snapshot: ThreadDetailSnapshot,
        requestCardPresentation: ThreadDetailRequestCardPresentation = ThreadDetailRequestCardPresentation(),
        options: ThreadDetailRenderOptions,
        revision: RenderRevision
    ) -> ThreadDetailRenderSnapshot {
        let filteredEvents = snapshot.events.filter { options.filter.includes($0) }
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
            hasUnfilteredEvents: !snapshot.events.isEmpty
        )
    }
}
