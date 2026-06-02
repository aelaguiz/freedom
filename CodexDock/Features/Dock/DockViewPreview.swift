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
                id: "preview-followup",
                title: "Audit the Dock snapshot model",
                status: .idle,
                lane: .human,
                sourceKind: .human,
                repository: "codex-client",
                workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                branch: "feature/human-only",
                activityAt: Date(timeIntervalSinceNow: -900),
                displaySummary: "Follow-up review notes are ready."
            )
        ]
        return ThreadCardStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            identityVersion: 1,
            projectionEngineVersion: 1,
            sourceHostID: host.id,
            view: .dock,
            scope: "view",
            viewParamsKey: "dock:\(host.id)",
            complete: true,
            totalRows: cards.count,
            window: DockStreamWindowDTO(offset: 0, limit: cards.count, rowCount: cards.count),
            epoch: "preview",
            seq: 1,
            order: "displayOrderKeyAscending",
            freshness: DockStreamFreshnessDTO(status: .fresh),
            rows: cards
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
        let projectionID = "host:\(host.id)/thread:\(id)/row:threadCard"
        return DockThreadCardDTO(
            schemaVersion: 1,
            identityVersion: 1,
            projectionEngineVersion: 1,
            sourceHostID: host.id,
            view: "dock",
            projectionID: projectionID,
            sourceRef: "host:\(host.id)/thread:\(id)",
            rowRole: "threadCard",
            displayOrderKey: String(format: "%019lld|0001|%@", Int64.max - activityAtMs, projectionID),
            id: projectionID,
            logicalHostID: host.id,
            threadID: id,
            backendSessionID: "preview-session-\(id)",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
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
