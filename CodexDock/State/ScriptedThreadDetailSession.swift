#if DEBUG
import Foundation

struct ScriptedThreadDetailSessionFactory: ThreadDetailSessionMaking {
    let scenario: ScriptedDockStreamScenario

    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        makeSession(for: host, foregroundWorkGate: nil)
    }

    func makeSession(
        for host: DockHostConfiguration,
        foregroundWorkGate: (any AppForegroundWorkGating)?
    ) -> any ThreadDetailSession {
        ScriptedThreadDetailSession(host: host, scenario: scenario)
    }
}

private actor ScriptedThreadDetailSession: ThreadDetailSession {
    nonisolated let connectionStates: AsyncStream<AppServerConnectionState>
    nonisolated let notifications: AsyncStream<JSONRPCNotification>
    nonisolated let serverRequests: AsyncStream<JSONRPCRequest>

    private let host: DockHostConfiguration
    private let scenario: ScriptedDockStreamScenario
    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation

    init(host: DockHostConfiguration, scenario: ScriptedDockStreamScenario) {
        self.host = host
        self.scenario = scenario
        let connectionStates = AsyncStream.makeStream(of: AppServerConnectionState.self)
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.connectionStates = connectionStates.stream
        self.connectionStateContinuation = connectionStates.continuation
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.connectionStateContinuation.yield(.idle)
    }

    func connectAndInitialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        connectionStateContinuation.yield(.connected)
        return InitializeResponse(
            userAgent: "scripted-codex-dock",
            codexHome: "/tmp/codex-client/scripted",
            platformFamily: "scripted",
            platformOs: "iOS"
        )
    }

    func threadRead(
        params: ThreadReadParams,
        timeout: Duration
    ) async throws -> ThreadReadResponseDTO {
        ThreadReadResponseDTO(thread: thread(threadID: params.threadId))
    }

    func threadTurnsList(
        params: ThreadTurnsListParams,
        timeout: Duration
    ) async throws -> ThreadTurnsListResponseDTO {
        guard params.cursor == nil else {
            return ThreadTurnsListResponseDTO(data: [])
        }
        return ThreadTurnsListResponseDTO(data: turns(threadID: params.threadId))
    }

    func threadResume(
        params: ThreadResumeParams,
        timeout: Duration
    ) async throws -> ThreadResumeResponseDTO {
        ThreadResumeResponseDTO(thread: thread(threadID: params.threadId))
    }

    func turnStart(
        params: TurnStartParams,
        timeout: Duration
    ) async throws -> TurnStartResponseDTO {
        TurnStartResponseDTO(turn: .object(["id": .string("scripted-turn")]))
    }

    func turnSteer(
        params: TurnSteerParams,
        timeout: Duration
    ) async throws -> TurnSteerResponseDTO {
        TurnSteerResponseDTO(turnId: params.expectedTurnId)
    }

    func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws {}

    func disconnect() async {
        connectionStateContinuation.yield(.closed(reason: "scripted detail closed"))
        connectionStateContinuation.finish()
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    private func thread(threadID: String) -> ThreadDTO {
        ThreadDTO(
            id: threadID,
            sessionId: "scripted-\(threadID)",
            preview: preview(threadID: threadID),
            createdAt: 1_779_990_000,
            updatedAt: updatedAt(threadID: threadID),
            status: .idle,
            cwd: "/tmp/codex-client/scripted",
            source: .string("cli"),
            gitInfo: ThreadGitInfoDTO(
                sha: "scripted",
                branch: "feature/relay-aggregator",
                originUrl: nil
            ),
            name: title(threadID: threadID),
            turns: []
        )
    }

    private func turns(threadID: String) -> [JSONValue] {
        if scenario == .messageNoise, threadID.hasSuffix("-noise") {
            return noisyTurns()
        }
        return genericMessageTurns(threadID: threadID)
    }

    private func noisyTurns() -> [JSONValue] {
        [
            .object([
                "id": .string("turn-message"),
                "startedAt": .integer(1_779_990_200),
                "items": .array([
                    .object([
                        "id": .string("message-stable"),
                        "type": .string("agentMessage"),
                        "text": .string("Stable true message before tool noise."),
                    ]),
                ]),
            ]),
            .object([
                "id": .string("turn-noise"),
                "startedAt": .integer(1_779_990_900),
                "items": .array([
                    .object([
                        "id": .string("reasoning-hidden"),
                        "type": .string("reasoning"),
                        "summary": .array([
                            .object(["text": .string("INTERNAL REASONING SHOULD NOT DISPLAY")]),
                        ]),
                    ]),
                    .object([
                        "id": .string("tool-hidden"),
                        "type": .string("commandExecution"),
                        "command": .array([.string("rtk"), .string("swift"), .string("test")]),
                        "aggregatedOutput": .string("TOOL OUTPUT SHOULD NOT DISPLAY"),
                    ]),
                ]),
            ]),
        ]
    }

    private func genericMessageTurns(threadID: String) -> [JSONValue] {
        [
            .object([
                "id": .string("turn-\(threadID)"),
                "startedAt": .integer(updatedAt(threadID: threadID)),
                "items": .array([
                    .object([
                        "id": .string("message-\(threadID)"),
                        "type": .string("agentMessage"),
                        "text": .string(preview(threadID: threadID)),
                    ]),
                ]),
            ]),
        ]
    }

    private func title(threadID: String) -> String {
        if threadID.hasSuffix("-noise") {
            return "Noisy Tool \(host.displayName)"
        }
        if threadID.hasSuffix("-newer-message") {
            return "True Newer \(host.displayName)"
        }
        return "Scripted detail \(host.displayName)"
    }

    private func preview(threadID: String) -> String {
        if threadID.hasSuffix("-noise") {
            return "Stable true message before tool noise."
        }
        if threadID.hasSuffix("-newer-message") {
            return "Newer true message keeps first place."
        }
        return "Scripted detail message."
    }

    private func updatedAt(threadID: String) -> Int64 {
        if threadID.hasSuffix("-noise") {
            return 1_779_990_900
        }
        if threadID.hasSuffix("-newer-message") {
            return 1_779_990_610
        }
        return 1_779_990_100
    }
}
#endif
