import Combine
import Foundation

public struct ArchiveSnapshot: Equatable, Sendable {
    public let hosts: [DockHostViewModel]
    public let hostStates: [DockHostStateViewModel]
    public let sections: [DockSectionViewModel]
    public let mappingFailures: [SessionSummaryMappingFailure]

    public var rowCount: Int {
        sections.reduce(0) { count, section in
            count + section.rows.count
        }
    }
}

public enum ArchiveStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case loaded(ArchiveSnapshot)
    case empty(ArchiveSnapshot)
}

@MainActor
public final class ArchiveStore: ObservableObject {
    @Published public private(set) var state: ArchiveStoreState
    @Published public private(set) var actionError: String?

    private var hosts: [DockHostConfiguration]
    private let loader: any DockSessionLoading
    private let archiver: any DockSessionArchiving
    private let metadataStore: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private var isLoading = false
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]

    public init(
        registry: HostRegistry,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.loader = loader
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.now = now
        self.state = .idle(registry.hosts.map(DockHostViewModel.init))
    }

    public init(
        configurationError error: Error,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = []
        self.loader = loader
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.now = now
        self.state = .configurationError(error.localizedDescription)
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        hosts = registry.hosts
        actionError = nil
        state = .idle(registry.hosts.map(DockHostViewModel.init))
        await reload(showLoading: true)
    }

    public func load() async {
        await reload(showLoading: true)
    }

    public func refresh() async {
        await reload(showLoading: false)
    }

    @discardableResult
    public func restore(_ row: DockRowViewModel) async -> Bool {
        guard let host = hosts.first(where: { $0.id == row.id.hostID }) else {
            actionError = "Host \(row.id.hostID) is no longer configured."
            return false
        }

        do {
            try await archiver.unarchiveThread(row.id.threadID, on: host)
            actionError = nil
            await refresh()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func reload(showLoading: Bool) async {
        guard !hosts.isEmpty else {
            return
        }
        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        if showLoading {
            state = .loading(hosts.map(DockHostViewModel.init))
        }

        do {
            localMetadata = try await metadataStore.load()
        } catch {
            localMetadata = [:]
        }

        let results = await loadAllHosts()
        let snapshot = makeSnapshot(results: results)
        state = snapshot.rowCount == 0 ? .empty(snapshot) : .loaded(snapshot)
    }

    private struct HostLoadOutcome: Sendable {
        let host: DockHostConfiguration
        let result: Result<DockLoadResult, DockLoadFailure>
    }

    private func loadAllHosts() async -> [HostLoadOutcome] {
        await withTaskGroup(of: HostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask { [loader] in
                    do {
                        return HostLoadOutcome(
                            host: host,
                            result: .success(try await loader.loadSessions(for: host, query: .archivedHuman))
                        )
                    } catch {
                        return HostLoadOutcome(
                            host: host,
                            result: .failure(Self.mapLoadFailure(error))
                        )
                    }
                }
            }

            var outcomes: [HostLoadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { lhs, rhs in
                hostIndex(lhs.host.id) < hostIndex(rhs.host.id)
            }
        }
    }

    private nonisolated static func mapLoadFailure(_ error: Error) -> DockLoadFailure {
        if let failure = error as? DockLoadFailure {
            return failure
        }
        return .error(error.localizedDescription)
    }

    private func makeSnapshot(results: [HostLoadOutcome]) -> ArchiveSnapshot {
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let result):
                summaries.append(contentsOf: result.summaries)
                mappingFailures.append(contentsOf: result.mappingFailures)
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: result.summaries.isEmpty
                            ? .empty
                            : .loaded(rowCount: result.summaries.count)
                    )
                )
            case .failure(let failure):
                switch failure {
                case .offline(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .offline(message)))
                case .error(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .error(message)))
                }
            }
        }

        let sections = SessionRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        ).sections(from: summaries)

        return ArchiveSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            sections: sections,
            mappingFailures: mappingFailures
        )
    }

    private func hostIndex(_ hostID: String) -> Int {
        hosts.firstIndex { $0.id == hostID } ?? Int.max
    }
}
