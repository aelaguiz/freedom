import Combine
import Foundation

enum DockScreenState: Equatable, Sendable {
    case configurationError(String)
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case loaded(DockRenderSnapshot)
}

@MainActor
final class DockScreenStore: ObservableObject {
    @Published private(set) var state: DockScreenState
    @Published private(set) var options: DockProjectionOptions
    @Published private(set) var searchText: String
    @Published private(set) var actionError: String?

    private let coalescer: RenderCoalescer<DockRenderSnapshot>
    private let now: @Sendable () -> Date
    private var renderTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var latestRevision = RenderRevision.zero

    init(
        hosts: [DockHostViewModel],
        options: DockProjectionOptions = DockProjectionOptions(),
        coalescer: RenderCoalescer<DockRenderSnapshot> = RenderCoalescer<DockRenderSnapshot>(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.state = .idle(hosts)
        self.options = options
        self.searchText = options.searchText
        self.coalescer = coalescer
        self.now = now
        self.actionError = nil
    }

    init(configurationError message: String) {
        self.state = .configurationError(message)
        self.options = DockProjectionOptions()
        self.searchText = ""
        self.coalescer = RenderCoalescer<DockRenderSnapshot>()
        self.now = Date.init
        self.actionError = nil
    }

    deinit {
        renderTask?.cancel()
        searchDebounceTask?.cancel()
    }

    func start() {
        guard renderTask == nil else {
            return
        }

        renderTask = Task { [weak self, coalescer] in
            let stream = await coalescer.stream()
            for await renderSnapshot in stream {
                await MainActor.run {
                    self?.state = .loaded(renderSnapshot)
                }
            }
        }
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
    }

    func setLoading(hosts: [DockHostViewModel]) {
        state = .loading(hosts)
    }

    func setIdle(hosts: [DockHostViewModel]) {
        state = .idle(hosts)
    }

    func setConfigurationError(_ message: String) {
        state = .configurationError(message)
    }

    func setActionError(_ message: String?) {
        actionError = message
    }

    func setLens(_ lens: DockLensID) {
        updateOptions(
            DockProjectionOptions(
                lens: lens,
                searchText: searchText,
                filters: options.filters
            ),
            syncSearchText: false
        )
    }

    func setSearchText(_ searchText: String) {
        self.searchText = searchText
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .milliseconds(CodexDockConstants.Rendering.searchDebounceMilliseconds)
                )
            } catch {
                return
            }
            await MainActor.run {
                self?.applySearchText(searchText)
            }
        }
    }

    private func applySearchText(_ searchText: String) {
        searchDebounceTask = nil
        updateOptions(
            DockProjectionOptions(
                lens: options.lens,
                searchText: searchText,
                filters: options.filters
            )
        )
    }

    func setFilters(_ filters: DockFilterState) {
        updateOptions(
            DockProjectionOptions(
                lens: options.lens,
                searchText: searchText,
                filters: filters
            ),
            syncSearchText: false
        )
    }

    func updateOptions(_ options: DockProjectionOptions, syncSearchText: Bool = true) {
        self.options = options
        if syncSearchText {
            searchText = options.searchText
        }
        guard case .loaded(let renderSnapshot) = state else {
            return
        }
        enqueueProjection(snapshot: renderSnapshot.snapshot)
    }

    func publish(snapshot: DockSnapshot) {
        enqueueProjection(snapshot: snapshot)
    }

    private func enqueueProjection(snapshot: DockSnapshot) {
        latestRevision = latestRevision.next()
        let revision = latestRevision
        let options = self.options
        let now = self.now
        let coalescer = self.coalescer
        if snapshot.rows.count > CodexDockConstants.Rendering.maxDockRowsPerMainPublish {
            DockLog.rendering.warning("dock render input exceeds main publish row budget rows=\(snapshot.rows.count, privacy: .public) budget=\(CodexDockConstants.Rendering.maxDockRowsPerMainPublish, privacy: .public)")
        }

        Task.detached(priority: .userInitiated) {
            let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.dockRenderProject)
            defer {
                DockSignpost.rendering.endInterval(RenderSignpostName.dockRenderProject, signpostState)
            }
            let renderSnapshot = DockRenderProjector(now: now).render(
                snapshot: snapshot,
                options: options,
                revision: revision
            )
            await coalescer.submit(renderSnapshot, revision: revision)
        }
    }
}
