import Foundation

@MainActor
public protocol DockCardStateProviding: AnyObject {
    var currentDockSnapshot: DockSnapshot? { get }
    func refresh() async
}
