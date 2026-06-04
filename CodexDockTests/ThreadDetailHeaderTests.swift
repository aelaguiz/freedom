import XCTest
@testable import CodexDock

final class ThreadDetailHeaderTests: XCTestCase {
    @MainActor
    func testThreadDetailHeaderUsesHumanStatusLabels() throws {
        let host = makeDetailHost()
        let cases: [(DockRowStatusKind, String?)] = [
            (.running, "Codex is working"),
            (.needsInput, "Your turn · Needs answer"),
            (.needsApproval, "Your turn · Needs approval"),
            (.idle, "Your turn · Ready"),
            (.error, "Error"),
            (.dormant, nil),
            (.unknown, nil),
        ]

        for (status, expectedLabel) in cases {
            let row = makeDetailRow(
                hostID: host.id,
                threadID: "thread-\(status.rawValue)",
                status: status
            )

            XCTAssertEqual(ThreadDetailHeader(host: host, row: row).statusLabel, expectedLabel)
        }
    }

    @MainActor
    func testForkedRowCarriesForkRelationshipIntoThreadDetailHeader() throws {
        let host = makeDetailHost()
        let row = makeDetailRow(
            hostID: host.id,
            threadID: "forked-thread",
            relationship: .forked
        )

        let header = ThreadDetailHeader(host: host, row: row)

        XCTAssertEqual(header.relationship, .forked)
    }
}
