#if DEBUG
import Foundation

enum ScriptedDockStreamScenario: String, Sendable {
    case retention
    case messageNoise
    case pinnedOrder
    case schemaMismatch
}

struct ScriptedDockStreamClient: ThreadCardStreamConnecting {
    let scenario: ScriptedDockStreamScenario

    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        ScriptedThreadCardStreamConnection(host: host, scenario: scenario)
    }
}

actor ScriptedThreadCardStreamConnection: ThreadCardStreamConnection {
    private let host: DockHostConfiguration
    private let scenario: ScriptedDockStreamScenario
    private let updateStream: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.Continuation
    private var updateTask: Task<Void, Never>?

    init(host: DockHostConfiguration, scenario: ScriptedDockStreamScenario) {
        self.host = host
        self.scenario = scenario
        let stream = AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
    }

    func subscribe() async throws -> ThreadCardStreamUpdateDTO {
        DockLog.dock.notice("dock stream subscribe started host_id=\(self.host.id, privacy: .public) scripted_scenario=\(self.scenario.rawValue, privacy: .public)")
        startScriptIfNeeded()
        let snapshot = snapshot(seq: 1, freshness: .fresh, cards: initialCards())
        DockLog.dock.notice("dock stream subscribe finished host_id=\(self.host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) scripted_scenario=\(self.scenario.rawValue, privacy: .public)")
        return snapshot
    }

    func resync() async throws -> ThreadCardStreamUpdateDTO {
        let snapshot = snapshot(seq: 4, freshness: .fresh, cards: resyncedCards())
        DockLog.dock.notice("dock stream scripted resync finished host_id=\(self.host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) rows=\(snapshot.cards?.count ?? 0, privacy: .public)")
        return snapshot
    }

    nonisolated func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error> {
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
                upsertCards: [approvalCard()]
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
                upsertCards: [needsInputCard()]
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
                upsertCards: [schemaRecoveredCard()]
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

    private func yield(_ update: ThreadCardStreamUpdateDTO) {
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
        cards: [DockThreadCardDTO]
    ) -> ThreadCardStreamUpdateDTO {
        ThreadCardStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: .dock,
            complete: true,
            totalRows: cards.count,
            window: DockStreamWindowDTO(offset: 0, limit: cards.count, rowCount: cards.count),
            stateGeneration: seq,
            epoch: host.id,
            seq: seq,
            asOf: iso8601(seq: seq),
            freshness: freshnessDTO(status: freshness, seq: seq, message: message),
            hosts: [
                DockStreamHostDTO(
                    id: host.id,
                    logicalHostID: host.displayName,
                    displayName: host.displayName,
                    endpoint: host.endpoint.displayEndpoint
                )
            ],
            cards: cards
        )
    }

    private func delta(
        schemaVersion: Int = CodexDockConstants.Dock.streamSchemaVersion,
        baseSeq: Int64,
        seq: Int64,
        freshness: DockStreamFreshnessStatus,
        message: String? = nil,
        upsertCards: [DockThreadCardDTO]
    ) -> ThreadCardStreamUpdateDTO {
        ThreadCardStreamUpdateDTO(
            kind: .delta,
            schemaVersion: schemaVersion,
            view: .dock,
            complete: true,
            totalRows: upsertCards.count,
            window: DockStreamWindowDTO(offset: 0, limit: upsertCards.count, rowCount: upsertCards.count),
            stateGeneration: seq,
            epoch: host.id,
            baseSeq: baseSeq,
            seq: seq,
            asOf: iso8601(seq: seq),
            freshness: freshnessDTO(status: freshness, seq: seq, message: message),
            upsertCards: upsertCards,
            deleteCardIDs: []
        )
    }

    private func heartbeat(
        seq: Int64,
        freshness: DockStreamFreshnessStatus,
        message: String? = nil
    ) -> ThreadCardStreamUpdateDTO {
        ThreadCardStreamUpdateDTO(
            kind: .heartbeat,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: .dock,
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

    private func initialCards() -> [DockThreadCardDTO] {
        if scenario == .messageNoise {
            return messageNoiseCards()
        }
        if scenario == .pinnedOrder {
            return pinnedOrderCards()
        }
        return [
            runningCard(),
            dormantCard()
        ]
    }

    private func resyncedCards() -> [DockThreadCardDTO] {
        if scenario == .messageNoise {
            return messageNoiseCards()
        }
        if scenario == .pinnedOrder {
            return pinnedOrderCards()
        }
        if scenario == .schemaMismatch {
            return [
                schemaRecoveredCard(),
                dormantCard(),
                needsInputCard()
            ]
        }
        return [
            approvalCard(),
            dormantCard(),
            needsInputCard()
        ]
    }

    private func runningCard() -> DockThreadCardDTO {
        card(
            key: "running",
            title: "Scripted running \(host.displayName)",
            status: .running,
            updatedAt: 1_779_990_100,
            summary: "Initial running row from the scripted stream.",
            source: .human
        )
    }

    private func approvalCard() -> DockThreadCardDTO {
        card(
            key: "running",
            title: "Scripted approval \(host.displayName)",
            status: .needsApproval,
            updatedAt: 1_779_990_300,
            summary: "Delta-updated row that should apply in place.",
            source: .human
        )
    }

    private func dormantCard() -> DockThreadCardDTO {
        card(
            key: "background",
            title: "Scripted background \(host.displayName)",
            status: .dormant,
            updatedAt: 1_779_990_000,
            summary: "Dormant rows must not render a default row badge.",
            source: .automation
        )
    }

    private func needsInputCard() -> DockThreadCardDTO {
        card(
            key: "needs-input",
            title: "Scripted input \(host.displayName)",
            status: .needsInput,
            updatedAt: 1_779_990_400,
            summary: "Resync row added after a forced sequence gap.",
            source: .automation
        )
    }

    private func schemaRecoveredCard() -> DockThreadCardDTO {
        card(
            key: "schema-recovered",
            title: "Scripted schema recovered \(host.displayName)",
            status: .needsApproval,
            updatedAt: 1_779_990_500,
            summary: "Resync row added after a forced schema mismatch.",
            source: .human
        )
    }

    private func pinnedOrderCards() -> [DockThreadCardDTO] {
        [
            card(
                key: "alpha",
                title: "Pinned Alpha visible \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_100,
                summary: "Alpha visible true message.",
                source: .human
            ),
            card(
                key: "bravo",
                title: "Pinned Bravo hidden \(host.displayName)",
                status: .needsInput,
                updatedAt: 1_779_990_200,
                summary: "Bravo hidden true message.",
                source: .human
            ),
            card(
                key: "charlie",
                title: "Pinned Charlie visible \(host.displayName)",
                status: .needsApproval,
                updatedAt: 1_779_990_300,
                summary: "Charlie visible true message.",
                source: .automation
            ),
            card(
                key: "delta",
                title: "Pinned Delta hidden \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_400,
                summary: "Delta hidden true message.",
                source: .automation
            )
        ]
    }

    private func messageNoiseCards() -> [DockThreadCardDTO] {
        [
            card(
                key: "newer-message",
                title: "True Newer \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_610,
                summary: "Newer true message keeps first place.",
                source: .human
            ),
            card(
                key: "noise",
                title: "Noisy Tool \(host.displayName)",
                status: .running,
                updatedAt: 1_779_990_900,
                summary: "TOOL OUTPUT SHOULD NOT DISPLAY",
                source: .automation,
                displaySummary: "Stable true message before tool noise.",
                activityAt: 1_779_990_200
            )
        ]
    }

    private func card(
        key: String,
        title: String,
        status: DockThreadCardStatus,
        updatedAt: Int64,
        summary: String,
        source: DockThreadCardSourceKind,
        displaySummary: String? = nil,
        activityAt: Int64? = nil
    ) -> DockThreadCardDTO {
        let threadID = "\(slug)-\(key)"
        let activitySeconds = activityAt ?? updatedAt
        return DockThreadCardDTO(
            id: "\(host.id)::\(key)",
            logicalHostID: host.displayName,
            threadID: threadID,
            backendSessionID: "scripted-\(threadID)",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            orderKey: orderKey(activitySeconds: activitySeconds, key: key),
            activityAt: iso8601(timestamp: activitySeconds),
            activityAtMs: activitySeconds * 1_000,
            displaySummary: displaySummary ?? summary,
            title: title,
            status: status,
            sourceKind: source,
            lane: source == .automation ? .agent : .human,
            archiveState: .active,
            freshness: .fresh,
            completeness: .complete,
            repository: "codex-client",
            workingDirectory: "/tmp/codex-client/scripted",
            branch: "feature/relay-aggregator",
            summarySource: displaySummary == nil ? "scripted_summary" : "scripted_display"
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

    private func iso8601(timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return ISO8601DateFormatter().string(from: date)
    }

    private func orderKey(activitySeconds: Int64, key: String) -> String {
        let inverted = Int64.max - activitySeconds
        return String(format: "%019lld:%@", inverted, key)
    }
}
#endif
