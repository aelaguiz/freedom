import CodexDock
import XCTest

@MainActor
final class CodexDockPerformanceScrollUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDockScrollGestureRunsWithPerformanceProfilingEnabled() throws {
        let app = launchRelayBackedCodexDockApp(
            hosts: Self.hosts,
            terminateFirst: true,
            additionalEnvironment: [
                "CODEX_DOCK_PERFORMANCE_PROFILING": "1",
                "CODEX_DOCK_UI_PROFILING": "1",
            ]
        )

        let root = app.displayedUIElement(id: AutomationID.Dock.root.rawValue)
        XCTAssertTrue(
            root.waitForDisplayedUIStringValue(matching: { value in
                value.contains("loaded") && !value.contains("Partial")
            }, timeout: 45),
            "Dock did not reach a complete loaded state before the performance scroll gesture.\n\nAccessibility tree:\n\(app.debugDescription)"
        )

        let before = app.captureDisplayedUISample(index: 0)
        XCTContext.runActivity(named: "before-scroll") { activity in
            activity.add(XCTAttachment(string: before.dockRootValue))
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "No app window was available for the performance scroll gesture.")
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        for _ in 0..<4 {
            start.press(forDuration: 0.08, thenDragTo: end)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        let after = app.captureDisplayedUISample(index: 1)
        XCTContext.runActivity(named: "after-scroll") { activity in
            activity.add(XCTAttachment(string: after.dockRootValue))
        }
    }

    private static var hosts: String {
        let environment = ProcessInfo.processInfo.environment
        if let hosts = environment["CODEX_DOCK_UI_TEST_HOSTS"], !hosts.isEmpty {
            return hosts
        }
        return "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510"
    }
}
