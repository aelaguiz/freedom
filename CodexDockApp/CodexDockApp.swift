import CodexDock
import SwiftUI

@main
@MainActor
struct CodexDockApp: App {
    init() {
        MetricKitDiagnosticsReporter.shared.start()
        DockLog.app.notice("Codex Dock app launch")
    }

    var body: some Scene {
        WindowGroup {
            CodexDockBootstrapView()
                .codexAutomationID(AutomationID.App.root)
        }
    }
}
