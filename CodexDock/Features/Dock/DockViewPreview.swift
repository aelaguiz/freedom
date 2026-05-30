import SwiftUI

#Preview {
    let host = try! DockHostConfiguration(host: "preview.invalid", port: CodexDockConstants.Ports.dockRelay)
    return CodexDockRootView(
        store: DockStore(host: host, streamClient: PreviewDockStreamClient())
    )
}

private struct PreviewDockStreamClient: DockStreamConnecting {
    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        PreviewDockStreamConnection(host: host)
    }
}

private struct PreviewDockStreamConnection: DockStreamConnection {
    let host: DockHostConfiguration

    func subscribe() async throws -> DockStreamUpdateDTO {
        snapshot()
    }

    func resync() async throws -> DockStreamUpdateDTO {
        snapshot()
    }

    func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func close() async {}

    private func snapshot() -> DockStreamUpdateDTO {
        DockStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: "dock",
            complete: true,
            totalRows: 3,
            window: DockStreamWindowDTO(offset: 0, limit: 3, rowCount: 3),
            stateGeneration: 1,
            epoch: "preview",
            seq: 1,
            freshness: DockStreamFreshnessDTO(status: .fresh),
            hosts: [DockStreamHostDTO(id: host.id, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
            sessions: [
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-running",
                    hostID: host.id,
                    threadID: "preview-running",
                    backendSessionID: "preview-session-running",
                    title: "Wire the iPhone shell to the real host",
                    status: .running,
                    lane: .human,
                    kindLabel: "Human",
                    repository: "codex-client",
                    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                    branch: "main",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -180).timeIntervalSince1970),
                    summary: "Generated the app target and Dock store.",
                    messageSummary: "Generated the app target and Dock store.",
                    messageUpdatedAt: Int64(Date(timeIntervalSinceNow: -180).timeIntervalSince1970),
                    source: DockStreamSourceDTO(kind: .human)
                ),
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-review",
                    hostID: host.id,
                    threadID: "preview-review",
                    backendSessionID: "preview-session-review",
                    title: "Review the live-host launch proof",
                    status: .needsInput,
                    lane: .human,
                    kindLabel: "Human",
                    repository: "codex",
                    workingDirectory: "/Users/aelaguiz/workspace/codex",
                    branch: "app-server",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -4_800).timeIntervalSince1970),
                    summary: "The simulator is connected to a reachable app-server.",
                    messageSummary: "The simulator is connected to a reachable app-server.",
                    messageUpdatedAt: Int64(Date(timeIntervalSinceNow: -4_800).timeIntervalSince1970),
                    source: DockStreamSourceDTO(kind: .human)
                ),
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-agent",
                    hostID: host.id,
                    threadID: "preview-agent",
                    backendSessionID: "preview-session-agent",
                    title: "Audit the Dock snapshot model",
                    status: .idle,
                    lane: .agent,
                    kindLabel: "Agent",
                    repository: "codex-client",
                    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                    branch: "feature/agents",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -900).timeIntervalSince1970),
                    summary: "Sub-agent returned a focused review.",
                    messageSummary: "Sub-agent returned a focused review.",
                    messageUpdatedAt: Int64(Date(timeIntervalSinceNow: -900).timeIntervalSince1970),
                    source: DockStreamSourceDTO(kind: .automation)
                )
            ]
        )
    }
}
