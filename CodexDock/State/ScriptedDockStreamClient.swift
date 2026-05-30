#if DEBUG
import Foundation

enum ScriptedDockStreamScenario: String, Sendable {
    case retention
    case messageNoise
    case pinnedOrder
    case schemaMismatch
}

struct ScriptedDockStreamClient: DockStreamConnecting {
    let scenario: ScriptedDockStreamScenario

    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        ScriptedDockStreamConnection(host: host, scenario: scenario)
    }
}

actor ScriptedDockStreamConnection: DockStreamConnection {
    private let host: DockHostConfiguration
    private let scenario: ScriptedDockStreamScenario
    private let updateStream: AsyncThrowingStream<DockStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<DockStreamUpdateDTO, Error>.Continuation
    private var updateTask: Task<Void, Never>?

    init(host: DockHostConfiguration, scenario: ScriptedDockStreamScenario) {
        self.host = host
        self.scenario = scenario
        let stream = AsyncThrowingStream<DockStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
    }

    func subscribe() async throws -> DockStreamUpdateDTO {
        DockLog.dock.notice("dock stream subscribe started host_id=\(self.host.id, privacy: .public) scripted_scenario=\(self.scenario.rawValue, privacy: .public)")
        startScriptIfNeeded()
        let snapshot = snapshot(seq: 1, freshness: .fresh, sessions: initialSessions())
        DockLog.dock.notice("dock stream subscribe finished host_id=\(self.host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) scripted_scenario=\(self.scenario.rawValue, privacy: .public)")
        return snapshot
    }

    func resync() async throws -> DockStreamUpdateDTO {
        let snapshot = snapshot(seq: 4, freshness: .fresh, sessions: resyncedSessions())
        DockLog.dock.notice("dock stream scripted resync finished host_id=\(self.host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) rows=\(snapshot.sessions?.count ?? 0, privacy: .public)")
        return snapshot
    }

    nonisolated func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        updateStream
    }

    func close() async {
        updateTask?.cancel()
        updateTask = nil
        updateContinuation.finish()
    }

    private func startScriptIfNeeded() {
        guard updateTask == nil else {
            return
        }
        updateTask = Task { [weak self] in
            await self?.runScript()
        }
    }

    private func runScript() async {
        switch scenario {
        case .retention:
            await runRetentionScript()
        case .messageNoise:
            await runMessageNoiseScript()
        case .pinnedOrder:
            await runPinnedOrderScript()
        case .schemaMismatch:
            await runSchemaMismatchScript()
        }
    }

    private func runRetentionScript() async {
        await sleep(milliseconds: 250)
        yield(heartbeat(seq: 1, freshness: .fresh))

        await sleep(milliseconds: 250)
        yield(
            delta(
                baseSeq: 1,
                seq: 2,
                freshness: .fresh,
                upsertSessions: [approvalSession()]
            )
        )

        await sleep(milliseconds: 250)
        yield(heartbeat(seq: 2, freshness: .stale, message: "Scripted slow refresh"))

        await sleep(milliseconds: 250)
        yield(
            delta(
                baseSeq: 99,
                seq: 3,
                freshness: .fresh,
                upsertSessions: [needsInputSession()]
            )
        )

        await sleep(milliseconds: 500)
        yield(heartbeat(seq: 4, freshness: .offline, message: "Scripted offline"))

        await sleep(milliseconds: 250)
        updateContinuation.finish()
    }

    private func runSchemaMismatchScript() async {
        await sleep(milliseconds: 250)
        yield(heartbeat(seq: 1, freshness: .fresh))

        await sleep(milliseconds: 250)
        yield(
            delta(
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1,
                baseSeq: 1,
                seq: 2,
                freshness: .fresh,
                upsertSessions: [schemaRecoveredSession()]
            )
        )
    }

    private func runPinnedOrderScript() async {
        await sleep(milliseconds: 250)
        yield(heartbeat(seq: 1, freshness: .fresh))
    }

    private func runMessageNoiseScript() async {
        await sleep(milliseconds: 250)
        yield(heartbeat(seq: 1, freshness: .fresh))
    }

    private func yield(_ update: DockStreamUpdateDTO) {
        guard !Task.isCancelled else {
            return
        }
        updateContinuation.yield(update)
    }

    private func sleep(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func snapshot(
        seq: Int64,
        freshness: DockStreamFreshnessStatus,
        message: String? = nil,
        sessions: [DockStreamSessionDTO]
    ) -> DockStreamUpdateDTO {
        DockStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: "dock",
            complete: true,
            totalRows: sessions.count,
            window: DockStreamWindowDTO(offset: 0, limit: sessions.count, rowCount: sessions.count),
            stateGeneration: seq,
            epoch: host.id,
            seq: seq,
            asOf: iso8601(seq: seq),
            freshness: freshnessDTO(status: freshness, seq: seq, message: message),
            hosts: [
                DockStreamHostDTO(
                    id: host.id,
                    displayName: host.displayName,
                    endpoint: host.endpoint.displayEndpoint
                )
            ],
            sessions: sessions
        )
    }

    private func delta(
        schemaVersion: Int = CodexDockConstants.Dock.streamSchemaVersion,
        baseSeq: Int64,
        seq: Int64,
        freshness: DockStreamFreshnessStatus,
        message: String? = nil,
        upsertSessions: [DockStreamSessionDTO]
    ) -> DockStreamUpdateDTO {
        DockStreamUpdateDTO(
            kind: .delta,
            schemaVersion: schemaVersion,
            view: "dock",
            complete: true,
            totalRows: upsertSessions.count,
            window: DockStreamWindowDTO(offset: 0, limit: upsertSessions.count, rowCount: upsertSessions.count),
            stateGeneration: seq,
            epoch: host.id,
            baseSeq: baseSeq,
            seq: seq,
            asOf: iso8601(seq: seq),
            freshness: freshnessDTO(status: freshness, seq: seq, message: message),
            upsertSessions: upsertSessions,
            deleteSessionIDs: []
        )
    }

    private func heartbeat(
        seq: Int64,
        freshness: DockStreamFreshnessStatus,
        message: String? = nil
    ) -> DockStreamUpdateDTO {
        DockStreamUpdateDTO(
            kind: .heartbeat,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: "dock",
            complete: true,
            stateGeneration: seq,
            epoch: host.id,
            seq: seq,
            asOf: iso8601(seq: seq),
            freshness: freshnessDTO(status: freshness, seq: seq, message: message)
        )
    }

    private func freshnessDTO(
        status: DockStreamFreshnessStatus,
        seq: Int64,
        message: String?
    ) -> DockStreamFreshnessDTO {
        DockStreamFreshnessDTO(
            status: status,
            lastAttemptAt: iso8601(seq: seq),
            lastSyncAt: status == .fresh ? iso8601(seq: seq) : nil,
            lastError: message
        )
    }

    private func initialSessions() -> [DockStreamSessionDTO] {
        if scenario == .messageNoise {
            return messageNoiseSessions()
        }
        if scenario == .pinnedOrder {
            return pinnedOrderSessions()
        }
        return [
            runningSession(),
            dormantSession()
        ]
    }

    private func resyncedSessions() -> [DockStreamSessionDTO] {
        if scenario == .messageNoise {
            return messageNoiseSessions()
        }
        if scenario == .pinnedOrder {
            return pinnedOrderSessions()
        }
        if scenario == .schemaMismatch {
            return [
                schemaRecoveredSession(),
                dormantSession(),
                needsInputSession()
            ]
        }
        return [
            approvalSession(),
            dormantSession(),
            needsInputSession()
        ]
    }

    private func runningSession() -> DockStreamSessionDTO {
        session(
            key: "running",
            title: "Scripted running \(host.displayName)",
            status: .running,
            updatedAt: 1_779_990_100,
            summary: "Initial running row from the scripted stream.",
            source: .human
        )
    }

    private func approvalSession() -> DockStreamSessionDTO {
        session(
            key: "running",
            title: "Scripted approval \(host.displayName)",
            status: .needsApproval,
            updatedAt: 1_779_990_300,
            summary: "Delta-updated row that should apply in place.",
            source: .human
        )
    }

    private func dormantSession() -> DockStreamSessionDTO {
        session(
            key: "background",
            title: "Scripted background \(host.displayName)",
            status: .dormant,
            updatedAt: 1_779_990_000,
            summary: "Dormant rows must not render a default row badge.",
            source: .automation
        )
    }

    private func needsInputSession() -> DockStreamSessionDTO {
        session(
            key: "needs-input",
            title: "Scripted input \(host.displayName)",
            status: .needsInput,
            updatedAt: 1_779_990_400,
            summary: "Resync row added after a forced sequence gap.",
            source: .automation
        )
    }

    private func schemaRecoveredSession() -> DockStreamSessionDTO {
        session(
            key: "schema-recovered",
            title: "Scripted schema recovered \(host.displayName)",
            status: .needsApproval,
            updatedAt: 1_779_990_500,
            summary: "Resync row added after a forced schema mismatch.",
            source: .human
        )
    }

    private func pinnedOrderSessions() -> [DockStreamSessionDTO] {
        [
            session(
                key: "alpha",
                title: "Pinned Alpha visible \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_100,
                summary: "Alpha visible true message.",
                source: .human
            ),
            session(
                key: "bravo",
                title: "Pinned Bravo hidden \(host.displayName)",
                status: .needsInput,
                updatedAt: 1_779_990_200,
                summary: "Bravo hidden true message.",
                source: .human
            ),
            session(
                key: "charlie",
                title: "Pinned Charlie visible \(host.displayName)",
                status: .needsApproval,
                updatedAt: 1_779_990_300,
                summary: "Charlie visible true message.",
                source: .automation
            ),
            session(
                key: "delta",
                title: "Pinned Delta hidden \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_400,
                summary: "Delta hidden true message.",
                source: .automation
            )
        ]
    }

    private func messageNoiseSessions() -> [DockStreamSessionDTO] {
        [
            session(
                key: "newer-message",
                title: "True Newer \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_610,
                summary: "Newer true message keeps first place.",
                source: .human
            ),
            session(
                key: "noise",
                title: "Noisy Tool \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_900,
                summary: "TOOL OUTPUT SHOULD NOT DISPLAY",
                source: .automation,
                messageSummary: "Stable true message before tool noise.",
                messageUpdatedAt: 1_779_990_200
            )
        ]
    }

    private func session(
        key: String,
        title: String,
        status: DockStreamSessionStatus,
        updatedAt: Int64,
        summary: String,
        source: DockStreamSourceKind,
        messageSummary: String? = nil,
        messageUpdatedAt: Int64? = nil
    ) -> DockStreamSessionDTO {
        let threadID = "\(slug)-\(key)"
        return DockStreamSessionDTO(
            id: "\(host.id)::\(key)",
            hostID: host.id,
            threadID: threadID,
            backendSessionID: "scripted-\(threadID)",
            title: title,
            status: status,
            lane: source == .automation ? .agent : .human,
            kindLabel: source == .automation ? "Agent" : "Human",
            repository: "codex-client",
            workingDirectory: "/tmp/codex-client/scripted",
            branch: "feature/relay-aggregator",
            updatedAt: updatedAt,
            summary: summary,
            messageSummary: messageSummary ?? summary,
            messageUpdatedAt: messageUpdatedAt ?? updatedAt,
            source: DockStreamSourceDTO(kind: source)
        )
    }

    private var slug: String {
        host.id.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .map(String.init)
        .joined()
    }

    private func iso8601(seq: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(1_779_990_000 + seq))
        return ISO8601DateFormatter().string(from: date)
    }
}
#endif
