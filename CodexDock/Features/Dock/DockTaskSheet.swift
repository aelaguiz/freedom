import SwiftUI

public enum DockTaskSheet: String, Identifiable, Sendable {
    case archiveCleanup
    case archivedThreads
    case systemHealth
    case relaySettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .archiveCleanup:
            return "Archive Cleanup"
        case .archivedThreads:
            return "Archived Threads"
        case .systemHealth:
            return "System Health"
        case .relaySettings:
            return "Relay Settings"
        }
    }
}

extension View {
    @ViewBuilder
    func dockTaskSheetPresentation() -> some View {
        #if os(iOS)
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}
