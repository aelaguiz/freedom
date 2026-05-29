@testable import CodexDock
import XCTest

final class AutomationIDTests: XCTestCase {
    func testStaticScreenIdentifiersAreStable() {
        XCTAssertEqual(AutomationID.App.root.rawValue, "codexdock.app.root")
        XCTAssertEqual(AutomationID.Bootstrap.root.rawValue, "codexdock.bootstrap.root")
        XCTAssertEqual(AutomationID.Root.tabs.rawValue, "codexdock.root.tabs")
        XCTAssertEqual(AutomationID.Dock.root.rawValue, "codexdock.dock.root")
        XCTAssertEqual(AutomationID.Archive.root.rawValue, "codexdock.archive.root")
        XCTAssertEqual(AutomationID.Relay.root.rawValue, "codexdock.relay.root")
    }

    func testDynamicRowAndCardIdentifiersEscapeUnsafeSegments() {
        XCTAssertEqual(
            AutomationID.Dock.row(hostID: "Amir M5.local:4510", threadID: "thread/one").rawValue,
            "codexdock.dock.row.Amir%20M5.local%3A4510.thread%2Fone"
        )
        XCTAssertEqual(
            AutomationID.RequestCard.approveButton(cardID: "request:{42}").rawValue,
            "codexdock.session.request.request%3A%7B42%7D.approve"
        )
    }

    func testSafeSegmentUsesPlaceholderForEmptyValues() {
        XCTAssertEqual(AutomationID.safeSegment(""), "_")
    }
}
