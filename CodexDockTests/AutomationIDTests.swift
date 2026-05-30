@testable import CodexDock
import XCTest

final class AutomationIDTests: XCTestCase {
    func testStaticScreenIdentifiersAreStable() {
        XCTAssertEqual(AutomationID.App.root.rawValue, "codexdock.app.root")
        XCTAssertEqual(AutomationID.Bootstrap.root.rawValue, "codexdock.bootstrap.root")
        XCTAssertEqual(AutomationID.Root.tabs.rawValue, "codexdock.root.tabs")
        XCTAssertEqual(AutomationID.Dock.root.rawValue, "codexdock.dock.root")
        XCTAssertEqual(AutomationID.Dock.lensPicker.rawValue, "codexdock.dock.lens")
        XCTAssertEqual(AutomationID.Dock.filterButton.rawValue, "codexdock.dock.filters.button")
        XCTAssertEqual(AutomationID.Dock.activeFilterSummary.rawValue, "codexdock.dock.filters.summary")
        XCTAssertEqual(AutomationID.Dock.filterSurface.rawValue, "codexdock.dock.filters.surface")
        XCTAssertEqual(AutomationID.Dock.pinnedSection.rawValue, "codexdock.dock.pinned.section")
        XCTAssertEqual(AutomationID.Dock.pinnedHeader.rawValue, "codexdock.dock.pinned.header")
        XCTAssertEqual(AutomationID.Dock.pinnedManageButton.rawValue, "codexdock.dock.pinned.manage")
        XCTAssertEqual(AutomationID.Dock.pinnedManageSheet.rawValue, "codexdock.dock.pinned.manage.sheet")
        XCTAssertEqual(AutomationID.Dock.pinnedShowAllButton.rawValue, "codexdock.dock.pinned.show-all")
        XCTAssertEqual(AutomationID.Dock.pinnedHiddenHint.rawValue, "codexdock.dock.pinned.hidden")
        XCTAssertEqual(AutomationID.Archive.root.rawValue, "codexdock.archive.root")
        XCTAssertEqual(AutomationID.Relay.root.rawValue, "codexdock.relay.root")
    }

    func testDynamicRowAndCardIdentifiersEscapeUnsafeSegments() {
        XCTAssertEqual(
            AutomationID.Dock.row(hostID: "Amir M5.local:4510", threadID: "thread/one").rawValue,
            "codexdock.dock.row.Amir%20M5.local%3A4510.thread%2Fone"
        )
        XCTAssertEqual(
            AutomationID.Dock.hostGroup("host::Amir M5.local:4510").rawValue,
            "codexdock.dock.group.host.host%3A%3AAmir%20M5.local%3A4510"
        )
        XCTAssertEqual(
            AutomationID.Dock.rowAction(hostID: "Amir M5.local:4510", threadID: "thread/one", action: .pin).rawValue,
            "codexdock.dock.row.Amir%20M5.local%3A4510.thread%2Fone.action.pin"
        )
        XCTAssertEqual(
            AutomationID.Dock.rowAction(hostID: "Amir M5.local:4510", threadID: "thread/one", action: .unpin).rawValue,
            "codexdock.dock.row.Amir%20M5.local%3A4510.thread%2Fone.action.unpin"
        )
        XCTAssertEqual(
            AutomationID.Dock.pinnedManageRow(hostID: "Amir M5.local:4510", threadID: "thread/one").rawValue,
            "codexdock.dock.pinned.manage.row.Amir%20M5.local%3A4510.thread%2Fone"
        )
        XCTAssertEqual(
            AutomationID.Dock.pinnedManageUnpinButton(hostID: "Amir M5.local:4510", threadID: "thread/one").rawValue,
            "codexdock.dock.pinned.manage.row.Amir%20M5.local%3A4510.thread%2Fone.unpin"
        )
        XCTAssertEqual(
            AutomationID.Dock.filterBranch("feature/dock").rawValue,
            "codexdock.dock.filters.branch.feature%2Fdock"
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
