import XCTest
@testable import CodexDock

final class DockStoreTests: XCTestCase {
    @MainActor
    func testLoadPublishesRowsGroupedByBranch() async {
        let host = makeHost()
        let now = Date(timeIntervalSince1970: 2_000)
        let summaries = [
            makeSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "feature/dock",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_880),
                prompt: "Build the Dock shell"
            ),
            makeSummary(
                hostID: host.id,
                threadID: "thread-b",
                branch: "main",
                status: .active(activeFlags: [.waitingOnUserInput]),
                lastActivity: Date(timeIntervalSince1970: 1_400),
                prompt: "Review the launch proof"
            )
        ]
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: summaries))),
            now: { now }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.host.displayName, "Amir-M5")
        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.sections.map(\.title), ["feature/dock", "main"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .running)
        XCTAssertEqual(snapshot.sections[0].rows[0].lastActivity, "2m ago")
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .needsMe)
    }

    @MainActor
    func testEmptyHostPublishesEmptyState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: [])))
        )

        await store.load()

        XCTAssertEqual(store.state, .empty(DockHostViewModel(host: host)))
    }

    @MainActor
    func testOfflineHostPublishesOfflineState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .failure(.offline("Connection refused")))
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .offline(DockHostViewModel(host: host), "Connection refused")
        )
    }

    @MainActor
    func testProtocolErrorPublishesErrorState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .failure(.error("Invalid response")))
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .error(DockHostViewModel(host: host), "Invalid response")
        )
    }

    @MainActor
    func testConfigurationErrorDoesNotLoad() async {
        let store = DockStore(
            configurationError: DockHostConfigurationError.missingEndpoint,
            loader: FakeDockSessionLoader(mode: .failure(.error("Should not load")))
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .configurationError(DockHostConfigurationError.missingEndpoint.localizedDescription)
        )
    }

    func testHostConfigurationReadsPhoneReachableEndpointAndTokenFile() throws {
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "test-token\n".write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let host = try DockHostConfiguration.fromEnvironment([
            "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS": "ws://192.168.50.117:4500",
            "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE": tokenFile.path,
            "CODEX_DOCK_REAL_HOST_ID": "Amir-M5",
            "CODEX_DOCK_REAL_HOST_NAME": "Amir-M5"
        ])

        XCTAssertEqual(host.id, "Amir-M5")
        XCTAssertEqual(host.displayName, "Amir-M5")
        XCTAssertEqual(host.webSocketURL.absoluteString, "ws://192.168.50.117:4500")
        XCTAssertEqual(host.bearerToken, "test-token")
    }

    func testHostConfigurationRejectsMissingEndpoint() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_APP_SERVER_BEARER_TOKEN": "test-token"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .missingEndpoint)
        }
    }
}

private enum FakeMode: Sendable {
    case success(DockLoadResult)
    case failure(DockLoadFailure)
}

private struct FakeDockSessionLoader: DockSessionLoading {
    let mode: FakeMode

    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}

private func makeHost() -> DockHostConfiguration {
    DockHostConfiguration(
        id: "Amir-M5",
        displayName: "Amir-M5",
        webSocketURL: URL(string: "ws://192.168.50.117:4500")!,
        bearerToken: "test-token"
    )
}

private func makeSummary(
    hostID: String,
    threadID: String,
    branch: String,
    status: SessionStatus,
    lastActivity: Date,
    prompt: String
) -> SessionSummary {
    SessionSummary(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        displayTitle: prompt,
        status: status,
        repository: .known("codex-client"),
        workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
        branch: .known(branch),
        lastActivity: lastActivity,
        shortEventSummary: .known("Assistant update for \(prompt)")
    )
}
