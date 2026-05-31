import XCTest
@testable import CodexDock

final class HostSettingsScreenStoreTests: XCTestCase {
    @MainActor
    func testHostSettingsStorePublishesRowsThroughScreenStore() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let tester = FakeThreadCardFixtureLoader(
            mode: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "thread-a",
                            branch: "main",
                            status: .active(activeFlags: []),
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Active row"
                        )
                    ]
                )
            )
        )
        let store = HostSettingsStore(registry: registry, tester: tester)

        await store.test(host.id)

        XCTAssertEqual(store.screenStore.rows.count, 1)
        XCTAssertEqual(
            store.screenStore.rows.map(\.status),
            [.online(rowCount: 1, checkedAt: store.screenStore.rows[0].status.checkedAtForTest)]
        )
    }
}

private extension HostConnectionTestStatus {
    var checkedAtForTest: Date {
        switch self {
        case .online(_, let checkedAt),
             .offline(_, let checkedAt),
             .error(_, let checkedAt):
            return checkedAt
        case .notChecked, .testing:
            return .distantPast
        }
    }
}
