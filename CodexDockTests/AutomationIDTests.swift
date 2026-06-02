@testable import CodexDock
import XCTest

final class AutomationIDTests: XCTestCase {
    func testStaticScreenIdentifiersAreStable() {
        XCTAssertEqual(AutomationID.App.root.rawValue, "codexdock.app.root")
        XCTAssertEqual(AutomationID.Bootstrap.root.rawValue, "codexdock.bootstrap.root")
        XCTAssertEqual(AutomationID.Dock.root.rawValue, "codexdock.dock.root")
        XCTAssertEqual(AutomationID.Dock.lensPicker.rawValue, "codexdock.dock.lens")
        XCTAssertEqual(AutomationID.Dock.filterButton.rawValue, "codexdock.dock.filters.button")
        XCTAssertEqual(AutomationID.Dock.activeFilterSummary.rawValue, "codexdock.dock.filters.summary")
        XCTAssertEqual(AutomationID.Dock.filterSurface.rawValue, "codexdock.dock.filters.surface")
        XCTAssertEqual(AutomationID.Dock.pinnedSection.rawValue, "codexdock.dock.pinned.section")
        XCTAssertEqual(AutomationID.Dock.pinnedHeader.rawValue, "codexdock.dock.pinned.header")
        XCTAssertEqual(AutomationID.Dock.pinnedToggleButton.rawValue, "codexdock.dock.pinned.toggle")
        XCTAssertEqual(AutomationID.Dock.pinnedReorderButton.rawValue, "codexdock.dock.pinned.reorder")
        XCTAssertEqual(AutomationID.Dock.pinnedReorderSheet.rawValue, "codexdock.dock.pinned.reorder.sheet")
        XCTAssertEqual(AutomationID.Dock.pinnedRowsList.rawValue, "codexdock.dock.pinned.rows")
        XCTAssertEqual(AutomationID.Dock.pinnedBodyDivider.rawValue, "codexdock.dock.pinned.body-divider")
        XCTAssertEqual(AutomationID.Dock.pinnedHiddenHint.rawValue, "codexdock.dock.pinned.hidden")
        XCTAssertEqual(AutomationID.Archive.root.rawValue, "codexdock.archive.root")
        XCTAssertEqual(AutomationID.Archive.retryFailedButton.rawValue, "codexdock.archive.batch.retry-failed")
        XCTAssertEqual(AutomationID.Archive.doneButton.rawValue, "codexdock.archive.batch.done")
        XCTAssertEqual(AutomationID.Relay.root.rawValue, "codexdock.relay.root")
        XCTAssertEqual(AutomationID.TaskSheet.moreButton.rawValue, "codexdock.tasks.more")
        XCTAssertEqual(AutomationID.SystemHealth.root.rawValue, "codexdock.system-health.root")
        XCTAssertEqual(AutomationID.ArchiveCleanup.root.rawValue, "codexdock.archive-cleanup.root")
        XCTAssertEqual(AutomationID.ArchiveCleanup.previewButton.rawValue, "codexdock.archive-cleanup.preview")
        XCTAssertEqual(AutomationID.ArchiveCleanup.reviewArchiveButton.rawValue, "codexdock.archive-cleanup.review-list.archive")
        XCTAssertEqual(AutomationID.ArchiveCleanup.confirmArchiveButton.rawValue, "codexdock.archive-cleanup.confirm.archive")
        XCTAssertEqual(AutomationID.ArchiveCleanup.doneButton.rawValue, "codexdock.archive-cleanup.progress.done")
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
            AutomationID.Dock.filterBranch("feature/dock").rawValue,
            "codexdock.dock.filters.branch.feature%2Fdock"
        )
        XCTAssertEqual(
            AutomationID.RequestCard.approveButton(cardID: "request:{42}").rawValue,
            "codexdock.session.request.request%3A%7B42%7D.approve"
        )
        XCTAssertEqual(
            AutomationID.TaskSheet.menuItem(.archiveCleanup).rawValue,
            "codexdock.tasks.menu.archiveCleanup"
        )
        XCTAssertEqual(
            AutomationID.SystemHealth.hostCard(hostID: "Amir M5.local:4510").rawValue,
            "codexdock.system-health.host.Amir%20M5.local%3A4510"
        )
        XCTAssertEqual(
            AutomationID.ArchiveCleanup.selectionToggle(hostID: "Amir M5.local:4510", threadID: "thread/one").rawValue,
            "codexdock.archive-cleanup.row.Amir%20M5.local%3A4510.thread%2Fone.select"
        )
    }

    func testSafeSegmentUsesPlaceholderForEmptyValues() {
        XCTAssertEqual(AutomationID.safeSegment(""), "_")
    }
}
