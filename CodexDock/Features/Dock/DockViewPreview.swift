import SwiftUI

#Preview {
    let host = try! DockHostConfiguration(host: "preview.invalid", port: CodexDockConstants.Ports.dockRelay)
    return CodexDockRootView(
        store: DockStore(host: host, streamClient: PreviewDockStreamClient())
    )
}

private struct PreviewDockStreamClient: ThreadCardStreamConnecting {
    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        PreviewThreadCardStreamConnection(host: host)
    }
}

private struct PreviewThreadCardStreamConnection: ThreadCardStreamConnection {
    let host: DockHostConfiguration

    func subscribe() async throws -> ThreadCardStreamUpdateDTO {
        snapshot()
    }

    func resync() async throws -> ThreadCardStreamUpdateDTO {
        snapshot()
    }

    func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func close() async {}

    private func snapshot() -> ThreadCardStreamUpdateDTO {
        let cards = [
            card(
                id: "preview-running",
                title: "Wire the iPhone shell to the real host",
                status: .running,
                lane: .human,
                sourceKind: .human,
                repository: "codex-client",
                workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                branch: "main",
                activityAt: Date(timeIntervalSinceNow: -180),
                displaySummary: "Generated the app target and Dock store."
            ),
            card(
                id: "preview-review",
                title: "Review the live-host launch proof",
                status: .needsInput,
                lane: .human,
                sourceKind: .human,
                repository: "codex",
                workingDirectory: "/Users/aelaguiz/workspace/codex",
                branch: "app-server",
                activityAt: Date(timeIntervalSinceNow: -4_800),
                displaySummary: "The simulator is connected to a reachable app-server."
            ),
            card(
                id: "preview-agent",
                title: "Audit the Dock snapshot model",
                status: .idle,
                lane: .agent,
                sourceKind: .automation,
                repository: "codex-client",
                workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                branch: "feature/agents",
                activityAt: Date(timeIntervalSinceNow: -900),
                displaySummary: "Sub-agent returned a focused review."
            )
        ]
        return ThreadCardStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: .dock,
            complete: true,
            totalRows: cards.count,
            window: DockStreamWindowDTO(offset: 0, limit: cards.count, rowCount: cards.count),
            stateGeneration: 1,
            epoch: "preview",
            seq: 1,
            freshness: DockStreamFreshnessDTO(status: .fresh),
            hosts: [DockStreamHostDTO(id: host.displayName, logicalHostID: host.displayName, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
            cards: cards
        )
    }

    private func card(
        id: String,
        title: String,
        status: DockThreadCardStatus,
        lane: DockThreadCardLane,
        sourceKind: DockThreadCardSourceKind,
        repository: String,
        workingDirectory: String,
        branch: String,
        activityAt: Date,
        displaySummary: String
    ) -> DockThreadCardDTO {
        let activityAtMs = Int64(activityAt.timeIntervalSince1970 * 1_000)
        return DockThreadCardDTO(
            id: "\(host.displayName)::\(id)",
            logicalHostID: host.displayName,
            threadID: id,
            backendSessionID: "preview-session-\(id)",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            orderKey: String(format: "%019lld:%@", Int64.max - activityAtMs, id),
            activityAt: ISO8601DateFormatter().string(from: activityAt),
            activityAtMs: activityAtMs,
            displaySummary: displaySummary,
            title: title,
            status: status,
            sourceKind: sourceKind,
            lane: lane,
            archiveState: .active,
            freshness: .fresh,
            completeness: .complete,
            repository: repository,
            workingDirectory: workingDirectory,
            branch: branch,
            summarySource: "preview"
        )
    }
}
