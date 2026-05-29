import Foundation

public struct SessionSummaryMappingResult: Equatable, Sendable {
    public let summaries: [SessionSummary]
    public let failures: [SessionSummaryMappingFailure]

    public init(
        summaries: [SessionSummary],
        failures: [SessionSummaryMappingFailure]
    ) {
        self.summaries = summaries
        self.failures = failures
    }
}

public struct SessionSummaryMappingFailure: Error, Equatable, Sendable {
    public let index: Int
    public let backendThreadID: String?
    public let reason: String

    public init(index: Int, backendThreadID: String?, reason: String) {
        self.index = index
        self.backendThreadID = backendThreadID
        self.reason = reason
    }
}

public enum SessionSummaryMapper {
    public static func map(
        response: ThreadListResponseDTO,
        hostID: String
    ) -> SessionSummaryMappingResult {
        var summaries: [SessionSummary] = []
        var failures: [SessionSummaryMappingFailure] = []

        for (index, thread) in response.data.enumerated() {
            switch map(thread: thread, hostID: hostID, index: index) {
            case .success(let summary):
                summaries.append(summary)
            case .failure(let failure):
                failures.append(failure)
            }
        }

        return SessionSummaryMappingResult(summaries: summaries, failures: failures)
    }

    private static func map(
        thread: ThreadDTO,
        hostID: String,
        index: Int
    ) -> Result<SessionSummary, SessionSummaryMappingFailure> {
        guard let threadID = nonEmpty(thread.id) else {
            return .failure(
                SessionSummaryMappingFailure(
                    index: index,
                    backendThreadID: nil,
                    reason: "missing thread id"
                )
            )
        }
        guard let sessionID = nonEmpty(thread.sessionId) else {
            return .failure(
                SessionSummaryMappingFailure(
                    index: index,
                    backendThreadID: threadID,
                    reason: "missing session id"
                )
            )
        }
        guard let timestamp = thread.updatedAt ?? thread.createdAt else {
            return .failure(
                SessionSummaryMappingFailure(
                    index: index,
                    backendThreadID: threadID,
                    reason: "missing last activity timestamp"
                )
            )
        }

        let preview = nonEmpty(thread.preview)
        let shortEventSummary = nonEmpty(thread.latestSummary)
            ?? latestMeaningfulSummary(from: thread)
            ?? preview
        let displayTitle = displayTitle(
            name: thread.name,
            preview: preview,
            cwd: thread.cwd,
            threadID: threadID
        )

        let summary = SessionSummary(
            id: HostScopedThreadID(hostID: hostID, threadID: threadID),
            backendSessionID: sessionID,
            displayTitle: displayTitle,
            status: status(from: thread.status),
            repository: repository(from: thread.gitInfo, cwd: thread.cwd),
            workingDirectory: text(from: thread.cwd),
            branch: text(from: thread.gitInfo?.branch),
            lastActivity: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            shortEventSummary: shortEventSummary.map { .known(collapsed($0)) } ?? .unknown,
            origin: origin(from: thread)
        )
        return .success(summary)
    }

    private static func latestMeaningfulSummary(from thread: ThreadDTO) -> String? {
        let messageEvents = ThreadEventNormalizer.events(from: thread).filter(isStoredMessageEvent)
        return messageEvents
            .max(by: eventPrecedes)
            .flatMap { nonEmpty($0.body) }
    }

    private static func isStoredMessageEvent(_ event: ThreadEvent) -> Bool {
        event.kind == .userMessage || (event.kind == .agentMessage && event.title == "Agent message")
    }

    private static func eventPrecedes(_ lhs: ThreadEvent, _ rhs: ThreadEvent) -> Bool {
        let lhsDate = lhs.displayGroupDate ?? lhs.date
        let rhsDate = rhs.displayGroupDate ?? rhs.date
        if let lhsDate, let rhsDate, lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        if lhsDate == nil, rhsDate != nil {
            return true
        }
        if lhsDate != nil, rhsDate == nil {
            return false
        }

        let lhsTurn = lhs.turnSequence ?? Int.min
        let rhsTurn = rhs.turnSequence ?? Int.min
        if lhsTurn != rhsTurn {
            return lhsTurn < rhsTurn
        }

        let lhsItem = lhs.itemSequence ?? Int.min
        let rhsItem = rhs.itemSequence ?? Int.min
        if lhsItem != rhsItem {
            return lhsItem < rhsItem
        }

        let lhsEvent = lhs.eventSequence ?? Int.min
        let rhsEvent = rhs.eventSequence ?? Int.min
        return lhsEvent < rhsEvent
    }

    private static func origin(from thread: ThreadDTO) -> SessionOrigin {
        let source = classifySource(thread.source)
        let threadSource = nonEmpty(thread.threadSource)
        let agentNickname = nonEmpty(thread.agentNickname)
        let agentRole = nonEmpty(thread.agentRole)
        let evidence = SessionOriginEvidence(
            sourceKind: source.sourceKind,
            rawSource: source.rawSource,
            threadSource: threadSource,
            agentNickname: agentNickname,
            agentRole: agentRole
        )
        let metadataSubtype = agentNickname != nil || agentRole != nil
            ? SessionAgentOriginSubtype.subAgentOther
            : subAgentSubtype(from: threadSource)

        if let sourceOrigin = source.origin, sourceOrigin.kind == .agentOrAutomation {
            return sourceOrigin.replacingEvidence(evidence)
        }

        if let sourceOrigin = source.origin,
           sourceOrigin.kind == .humanInteractive,
           metadataSubtype != nil {
            return .unknown(
                evidence: SessionOriginEvidence(
                    sourceKind: .unknown,
                    rawSource: evidence.rawSource,
                    threadSource: evidence.threadSource,
                    agentNickname: evidence.agentNickname,
                    agentRole: evidence.agentRole
                )
            )
        }

        if let metadataSubtype {
            return .agentOrAutomation(subtype: metadataSubtype, evidence: evidence)
        }

        if let sourceOrigin = source.origin {
            return sourceOrigin.replacingEvidence(evidence)
        }

        return .unknown(evidence: evidence)
    }

    private struct SourceClassification {
        let origin: SessionOrigin?
        let sourceKind: ThreadSourceKind?
        let rawSource: JSONValue?
    }

    fileprivate enum RecognizedSourceSignal: Hashable {
        case human(SessionHumanOriginSubtype, sourceKind: ThreadSourceKind?)
        case automation(SessionAgentOriginSubtype, sourceKind: ThreadSourceKind)
        case unknown

        var originKind: SessionOriginKind {
            switch self {
            case .human:
                return .humanInteractive
            case .automation:
                return .agentOrAutomation
            case .unknown:
                return .unknown
            }
        }

        var sourceKind: ThreadSourceKind? {
            switch self {
            case .human(_, let sourceKind):
                return sourceKind
            case .automation(_, let sourceKind):
                return sourceKind
            case .unknown:
                return .unknown
            }
        }
    }

    private static func classifySource(_ source: JSONValue?) -> SourceClassification {
        guard let source else {
            return SourceClassification(origin: nil, sourceKind: nil, rawSource: nil)
        }

        let signals = source.recognizedSourceSignals
        if signals.isEmpty {
            return SourceClassification(
                origin: .unknown(),
                sourceKind: .unknown,
                rawSource: source
            )
        }
        if signals.contains(.unknown) {
            return SourceClassification(
                origin: .unknown(),
                sourceKind: .unknown,
                rawSource: source
            )
        }

        let uniqueSignals = Set(signals)
        guard uniqueSignals.count == 1, let signal = signals.first else {
            return SourceClassification(
                origin: .unknown(),
                sourceKind: .unknown,
                rawSource: source
            )
        }

        switch signal {
        case .human(let subtype, let sourceKind):
            return SourceClassification(
                origin: .humanInteractive(subtype: subtype),
                sourceKind: sourceKind,
                rawSource: source
            )
        case .automation(let subtype, let sourceKind):
            return SourceClassification(
                origin: .agentOrAutomation(subtype: subtype),
                sourceKind: sourceKind,
                rawSource: source
            )
        case .unknown:
            return SourceClassification(
                origin: .unknown(),
                sourceKind: .unknown,
                rawSource: source
            )
        }
    }

    fileprivate static func sourceSignal(fromName name: String) -> RecognizedSourceSignal? {
        switch normalizedOriginToken(name) {
        case "cli":
            return .human(.cli, sourceKind: .cli)
        case "vscode", "vs":
            return .human(.vscode, sourceKind: .vscode)
        case "atlas":
            return .human(.customInteractive("atlas"), sourceKind: nil)
        case "chatgpt":
            return .human(.customInteractive("chatgpt"), sourceKind: nil)
        case "exec":
            return .automation(.exec, sourceKind: .exec)
        case "appserver", "mcp":
            return .automation(.appServer, sourceKind: .appServer)
        case "subagent", "subagentother", "other":
            return .automation(.subAgentOther, sourceKind: .subAgentOther)
        case "subagentreview", "review":
            return .automation(.subAgentReview, sourceKind: .subAgentReview)
        case "subagentcompact", "compact":
            return .automation(.subAgentCompact, sourceKind: .subAgentCompact)
        case "subagentthreadspawn", "threadspawn", "threadspawning", "spawn":
            return .automation(.subAgentThreadSpawn, sourceKind: .subAgentThreadSpawn)
        case "unknown":
            return .unknown
        default:
            return nil
        }
    }

    private static func subAgentSubtype(from threadSource: String?) -> SessionAgentOriginSubtype? {
        guard let threadSource else {
            return nil
        }
        guard case .automation(let subtype, _)? = sourceSignal(fromName: threadSource) else {
            return nil
        }
        return subtype
    }

    fileprivate static func normalizedOriginToken(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func status(from status: ThreadStatusDTO?) -> SessionStatus {
        guard let status else {
            return .unknown
        }

        switch status {
        case .notLoaded:
            return .notLoaded
        case .idle:
            return .idle
        case .systemError:
            return .systemError
        case .active(let activeFlags):
            return .active(activeFlags: activeFlags.map(activeFlag(from:)))
        case .unknown:
            return .unknown
        }
    }

    private static func activeFlag(from flag: ThreadActiveFlagDTO) -> SessionActiveFlag {
        switch flag {
        case .waitingOnApproval:
            return .waitingOnApproval
        case .waitingOnUserInput:
            return .waitingOnUserInput
        case .unknown(let value):
            return .unknown(value)
        }
    }

    private static func displayTitle(
        name: String?,
        preview: String?,
        cwd: String?,
        threadID: String
    ) -> String {
        if let name = nonEmpty(name) {
            return collapsed(name, maxLength: 80)
        }
        if let preview {
            return collapsed(preview, maxLength: 80)
        }
        if let cwd = nonEmpty(cwd), let lastComponent = lastPathComponent(cwd) {
            return lastComponent
        }
        return "Thread \(threadID)"
    }

    private static func repository(
        from gitInfo: ThreadGitInfoDTO?,
        cwd: String?
    ) -> SessionSummaryText {
        if let originUrl = nonEmpty(gitInfo?.originUrl),
           let repository = repositoryName(fromOriginURL: originUrl) {
            return .known(repository)
        }
        if let cwd = nonEmpty(cwd), let repository = lastPathComponent(cwd) {
            return .known(repository)
        }
        return .unknown
    }

    private static func text(from value: String?) -> SessionSummaryText {
        nonEmpty(value).map(SessionSummaryText.known) ?? .unknown
    }

    private static func repositoryName(fromOriginURL originURL: String) -> String? {
        let components = originURL.split { character in
            character == "/" || character == ":"
        }
        guard var name = components.last.map(String.init) else {
            return nil
        }
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return nonEmpty(name)
    }

    private static func lastPathComponent(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return nonEmpty(URL(fileURLWithPath: trimmed).lastPathComponent)
    }

    private static func collapsed(_ value: String, maxLength: Int = 140) -> String {
        let firstLine = value
            .components(separatedBy: .newlines)
            .first ?? value
        let collapsed = firstLine
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard collapsed.count > maxLength else {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: max(0, maxLength - 3))
        return String(collapsed[..<end]) + "..."
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension JSONValue {
    var recognizedSourceSignals: [SessionSummaryMapper.RecognizedSourceSignal] {
        switch self {
        case .string(let value):
            return SessionSummaryMapper.sourceSignal(fromName: value).map { [$0] } ?? []
        case .object(let values):
            var signals: [SessionSummaryMapper.RecognizedSourceSignal] = []
            for key in values.keys where !key.isSubAgentSourceKey {
                if let signal = SessionSummaryMapper.sourceSignal(fromName: key) {
                    signals.append(signal)
                }
            }
            for key in ["type", "kind", "sourceKind", "source_kind", "subtype"] {
                if case .string(let value)? = values[key] {
                    if let signal = SessionSummaryMapper.sourceSignal(fromName: value) {
                        signals.append(signal)
                    }
                }
            }
            if case .string(let value)? = values["custom"] {
                if let signal = SessionSummaryMapper.sourceSignal(fromName: value) {
                    signals.append(signal)
                }
            }
            if let nestedSource = values["source"] {
                signals.append(contentsOf: nestedSource.recognizedSourceSignals)
            }
            if let subAgent = values["subAgent"] ?? values["subagent"] {
                signals.append(contentsOf: subAgent.recognizedSubAgentSignals)
            }
            return signals.removingDuplicates()
        case .array(let values):
            return values.flatMap(\.recognizedSourceSignals).removingDuplicates()
        case .null, .bool, .integer, .double:
            return []
        }
    }

    var recognizedSubAgentSignals: [SessionSummaryMapper.RecognizedSourceSignal] {
        switch self {
        case .string(let value):
            return SessionSummaryMapper.sourceSignal(fromName: value).map { [$0] } ?? []
        case .object(let values):
            var signals: [SessionSummaryMapper.RecognizedSourceSignal] = []
            for key in values.keys {
                if let signal = SessionSummaryMapper.sourceSignal(fromName: key) {
                    signals.append(signal)
                }
            }
            for key in ["type", "kind", "variant", "subtype"] {
                if case .string(let value)? = values[key] {
                    if let signal = SessionSummaryMapper.sourceSignal(fromName: value) {
                        signals.append(signal)
                    }
                }
            }
            return signals.removingDuplicates()
        case .array(let values):
            return values.flatMap(\.recognizedSubAgentSignals).removingDuplicates()
        case .null, .bool, .integer, .double:
            return []
        }
    }
}

private extension String {
    var isSubAgentSourceKey: Bool {
        switch SessionSummaryMapper.normalizedOriginToken(self) {
        case "subagent":
            return true
        default:
            return false
        }
    }
}

private extension Sequence where Element: Equatable {
    func removingDuplicates() -> [Element] {
        var result: [Element] = []
        for element in self where !result.contains(element) {
            result.append(element)
        }
        return result
    }
}
