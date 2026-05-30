import Foundation

struct ThreadDetailRenderOptions: Equatable, Sendable {
    let filter: ThreadDetailMessageFilter
    let visibleLimit: Int

    init(
        filter: ThreadDetailMessageFilter = .default,
        visibleLimit: Int = CodexDockConstants.Rendering.threadInitialVisibleWindowRows
    ) {
        self.filter = filter
        self.visibleLimit = visibleLimit
    }
}

struct ThreadVisibleWindow: Equatable, Sendable {
    let startIndex: Int
    let rows: [ThreadEventRenderRow]
    let totalMatchingCount: Int
}

struct ThreadEventRenderRow: Equatable, Identifiable, Sendable {
    let event: ThreadEvent
    let requestCard: ServerRequestCard?

    var id: String {
        event.id
    }
}

struct ThreadDetailRenderSnapshot: Equatable, Sendable {
    let revision: RenderRevision
    let header: ThreadDetailHeader
    let liveState: ThreadDetailLiveState
    let options: ThreadDetailRenderOptions
    let visibleWindow: ThreadVisibleWindow
    let hasUnfilteredEvents: Bool

    var rows: [ThreadEventRenderRow] {
        visibleWindow.rows
    }
}
