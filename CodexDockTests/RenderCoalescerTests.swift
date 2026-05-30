import XCTest
@testable import CodexDock

final class RenderCoalescerTests: XCTestCase {
    func testRenderRevisionOrderingAndNextRevision() {
        let initial = RenderRevision(rawValue: 41)
        let next = initial.next()

        XCTAssertLessThan(initial, next)
        XCTAssertEqual(next.rawValue, 42)
    }

    func testCoalescerDropsOlderRevisionsAndPublishesLatest() async {
        let coalescer = RenderCoalescer<String>()
        let snapshots = await coalescer.stream()

        await coalescer.submit("first", revision: RenderRevision(rawValue: 1))
        await coalescer.submit("stale", revision: RenderRevision(rawValue: 0))
        await coalescer.submit("latest", revision: RenderRevision(rawValue: 2))
        await coalescer.finish()

        var received: [String] = []
        for await snapshot in snapshots {
            received.append(snapshot)
        }

        let latestRevision = await coalescer.latestRevision()
        XCTAssertEqual(latestRevision, RenderRevision(rawValue: 2))
        XCTAssertEqual(received, ["latest"])
    }

    func testRenderingConstantsMatchPhaseZeroPlan() {
        XCTAssertEqual(CodexDockConstants.Rendering.mainPublishWarningBudgetMilliseconds, 2)
        XCTAssertEqual(CodexDockConstants.Rendering.mainPublishCriticalBudgetMilliseconds, 4)
        XCTAssertTrue(CodexDockConstants.Rendering.dockRenderDropsSupersededRevisions)
        XCTAssertEqual(CodexDockConstants.Rendering.searchDebounceMilliseconds, 80)
        XCTAssertEqual(CodexDockConstants.Rendering.voiceTranscriptPublishDebounceMilliseconds, 50)
        XCTAssertEqual(CodexDockConstants.Rendering.threadInitialVisibleWindowRows, 240)
        XCTAssertEqual(CodexDockConstants.Rendering.threadPaginationPrefetchThresholdRows, 60)
        XCTAssertEqual(CodexDockConstants.Rendering.maxDockRowsPerMainPublish, 600)
        XCTAssertEqual(CodexDockConstants.Rendering.renderStreamBufferNewest, 1)
    }
}
