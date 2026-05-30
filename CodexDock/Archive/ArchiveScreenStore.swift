import Combine
import Foundation

@MainActor
public final class ArchiveScreenStore: ObservableObject {
    @Published public private(set) var state: ArchiveStoreState
    @Published public private(set) var actionError: String?

    public init(state: ArchiveStoreState, actionError: String? = nil) {
        self.state = state
        self.actionError = actionError
    }

    public func setState(_ state: ArchiveStoreState) {
        self.state = state
    }

    public func setActionError(_ message: String?) {
        actionError = message
    }
}
