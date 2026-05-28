import CodexDock
import SwiftUI

@main
@MainActor
struct CodexDockApp: App {
    var body: some Scene {
        WindowGroup {
            CodexDockBootstrapView()
        }
    }
}
