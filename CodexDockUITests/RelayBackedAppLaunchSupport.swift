import XCTest

@MainActor
func launchRelayBackedCodexDockApp(
    hosts: String? = nil,
    terminateFirst: Bool = false,
    additionalEnvironment: [String: String] = [:]
) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["CODEX_DOCK_HOSTS"] = hosts
        ?? ProcessInfo.processInfo.environment["CODEX_DOCK_UI_TEST_HOSTS"]
        ?? "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
    app.launchEnvironment["CODEX_DOCK_AUTOMATION_SNAPSHOTS"] = "1"
    for (key, value) in additionalEnvironment {
        app.launchEnvironment[key] = value
    }
    if terminateFirst {
        app.terminate()
    }
    app.launch()
    return app
}
