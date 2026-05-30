import XCTest
@testable import CodexDock

final class ThreadDetailHeaderTests: XCTestCase {
    @MainActor
    func testDormantRowDoesNotShowNotLoadedAsThreadDetailStatus() throws {
        let host = makeDetailHost()
        let dormantRow = makeDetailRow(
            hostID: host.id,
            threadID: "thread-1",
            status: .dormant
        )
        let runningRow = makeDetailRow(
            hostID: host.id,
            threadID: "thread-2",
            status: .running
        )

        XCTAssertNil(ThreadDetailHeader(host: host, row: dormantRow).statusLabel)
        XCTAssertEqual(ThreadDetailHeader(host: host, row: runningRow).statusLabel, "Running")
    }
}
