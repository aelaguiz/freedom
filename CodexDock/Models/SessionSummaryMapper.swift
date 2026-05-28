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
            shortEventSummary: preview.map { .known(collapsed($0)) } ?? .unknown
        )
        return .success(summary)
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
