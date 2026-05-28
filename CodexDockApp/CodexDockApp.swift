import CodexDock
import SwiftUI

@main
@MainActor
struct CodexDockApp: App {
    private let store: DockStore

    init() {
        self.store = Self.makeStore()
    }

    var body: some Scene {
        WindowGroup {
            CodexDockRootView(store: store)
        }
    }

    private static func makeStore() -> DockStore {
        do {
            return DockStore(host: try DockHostConfiguration.fromEnvironment())
        } catch {
            return DockStore(configurationError: error)
        }
    }
}
