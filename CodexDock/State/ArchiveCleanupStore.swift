import Combine
import Foundation

@MainActor
public final class ArchiveCleanupStore: ObservableObject {
    @Published public private(set) var state: ArchiveCleanupStoreState
    @Published public private(set) var selectedRowIDs: Set<HostScopedThreadID> = []
    @Published public private(set) var executionResults: [ArchiveCleanupExecutionResult] = []
    @Published public private(set) var isExecuting = false
    @Published public private(set) var stopRemainingRequested = false
    @Published public private(set) var executionTotalCount = 0

    private var hosts: [DockHostConfiguration]
    private var dataEngine: ArchiveCleanupDataEngine?
    private let archiver: any DockSessionArchiving

    public init(
        registry: HostRegistry,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.archiver = archiver
        self.dataEngine = ArchiveCleanupDataEngine(
            registry: registry,
            loader: loader,
            metadataStore: metadataStore,
            now: now
        )
        self.state = .idle(registry.hosts.map(DockHostViewModel.init))
    }

    public init(configurationError error: Error) {
        self.hosts = []
        self.archiver = AppServerDockClient()
        self.dataEngine = nil
        self.state = .configurationError(error.localizedDescription)
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        hosts = registry.hosts
        if let dataEngine {
            await dataEngine.updateRegistry(registry)
        }
        state = .idle(registry.hosts.map(DockHostViewModel.init))
        selectedRowIDs = []
    }

    public func loadPreview(rule: ArchiveCleanupRule) async {
        guard let dataEngine else {
            state = .failed("Archive cleanup is not configured.")
            return
        }
        state = .loading(hosts.map(DockHostViewModel.init))
        let preview = await dataEngine.loadPreview(rule: rule)
        if let message = preview.unavailableMessage {
            state = .failed(message)
            selectedRowIDs = []
        } else {
            state = .preview(preview)
            selectedRowIDs = Set(preview.candidates.map(\.id))
        }
        executionResults = []
        executionTotalCount = 0
    }

    public func setSelected(_ selected: Bool, rowID: HostScopedThreadID) {
        if selected {
            selectedRowIDs.insert(rowID)
        } else {
            selectedRowIDs.remove(rowID)
        }
    }

    public func stopRemaining() {
        stopRemainingRequested = true
    }

    @discardableResult
    public func archiveSelected() async -> [ArchiveCleanupExecutionResult] {
        guard case .preview(let preview) = state else {
            return []
        }
        let rows = preview.candidates.filter { selectedRowIDs.contains($0.id) }
        return await archiveRows(rows)
    }

    @discardableResult
    public func archiveFailedResults() async -> [ArchiveCleanupExecutionResult] {
        guard case .preview(let preview) = state else {
            return []
        }
        let failedRowIDs = Set(
            executionResults.compactMap { result -> HostScopedThreadID? in
                if case .failed = result.status {
                    return result.row.id
                }
                return nil
            }
        )
        let rows = preview.candidates.filter { failedRowIDs.contains($0.id) }
        return await archiveRows(rows)
    }

    private func archiveRows(
        _ rows: [DockRowViewModel]
    ) async -> [ArchiveCleanupExecutionResult] {
        guard !rows.isEmpty else {
            return []
        }

        isExecuting = true
        stopRemainingRequested = false
        executionResults = []
        executionTotalCount = rows.count
        defer {
            isExecuting = false
        }

        var results: [ArchiveCleanupExecutionResult] = []
        for row in rows {
            if stopRemainingRequested {
                results.append(ArchiveCleanupExecutionResult(row: row, status: .skipped))
                executionResults = results
                continue
            }
            guard let host = hosts.first(where: { $0.id == row.id.hostID }) else {
                results.append(ArchiveCleanupExecutionResult(row: row, status: .failed("Host is no longer configured.")))
                executionResults = results
                continue
            }
            do {
                try await archiver.archiveThread(row.id.threadID, on: host)
                selectedRowIDs.remove(row.id)
                results.append(ArchiveCleanupExecutionResult(row: row, status: .archived))
            } catch {
                results.append(ArchiveCleanupExecutionResult(row: row, status: .failed(error.localizedDescription)))
            }
            executionResults = results
        }
        executionResults = results
        return results
    }
}
