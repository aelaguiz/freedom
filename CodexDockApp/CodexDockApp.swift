import CodexDock
import SwiftUI

@main
@MainActor
struct CodexDockApp: App {
    private let rootView: CodexDockRootView

    init() {
        self.rootView = Self.makeRootView()
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    private static func makeRootView() -> CodexDockRootView {
        do {
            return CodexDockRootView(registry: try HostRegistry.fromEnvironment())
        } catch {
            return CodexDockRootView(configurationError: error)
        }
    }
}
