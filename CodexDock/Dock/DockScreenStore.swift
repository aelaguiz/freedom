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
    private let automationSnapshotStore: DockAutomationSnapshotStore?
    private let now: @Sendable () -> Date
    private var renderTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var latestRevision = RenderRevision.zero
    private var lastAcceptedInput: DockRenderInputKey?

    init(
        hosts: [DockHostViewModel],
        options: DockProjectionOptions = DockProjectionOptions(),
        coalescer: RenderCoalescer<DockRenderSnapshot> = RenderCoalescer<DockRenderSnapshot>(),
        automationSnapshotStore: DockAutomationSnapshotStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.state = .idle(hosts)
        self.options = options
        self.searchText = options.searchText
        self.coalescer = coalescer
        self.automationSnapshotStore = automationSnapshotStore
        self.now = now
        self.actionError = nil
    }

    init(configurationError message: String) {
        self.state = .configurationError(message)
        self.options = DockProjectionOptions()
        self.searchText = ""
        self.coalescer = RenderCoalescer<DockRenderSnapshot>()
        self.automationSnapshotStore = nil
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

        let automationSnapshotStore = automationSnapshotStore
        renderTask = Task { [weak self, coalescer, automationSnapshotStore] in
            let stream = await coalescer.stream()
            for await renderSnapshot in stream {
                let publishStartedAt = Date()
                let publishedSnapshot: DockRenderSnapshot
                if let automationSnapshotStore {
                    do {
                        let metadata = try automationSnapshotStore.write(
                            renderSnapshot: renderSnapshot,
                            options: renderSnapshot.options
                        )
                        publishedSnapshot = renderSnapshot.withAutomationSnapshot(metadata)
                    } catch {
                        await MainActor.run {
                            self?.actionError = "Dock automation snapshot failed: \(error.localizedDescription)"
                        }
                        DockLog.rendering.error("dock automation snapshot write failed revision=\(renderSnapshot.revision.rawValue, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
                        continue
                    }
                } else {
                    publishedSnapshot = renderSnapshot
                }
                await MainActor.run {
                    self?.state = .loaded(publishedSnapshot)
                    PerformanceProbe.event(
                        "dock.main_publish",
                        fields: [
                            "revision": "\(publishedSnapshot.revision.rawValue)",
                            "rows": "\(publishedSnapshot.snapshot.rows.count)",
                            "visible_rows": "\(publishedSnapshot.projection.automationRows.count)",
                            "groups": "\(publishedSnapshot.projection.groups.count)",
                            "pinned_rows": "\(publishedSnapshot.projection.pinnedRows.count)",
                            "hosts": "\(publishedSnapshot.snapshot.hosts.count)",
                            "automation_snapshot": "\(publishedSnapshot.automationSnapshot != nil)",
                            "duration_ms": "\(PerformanceProbe.milliseconds(since: publishStartedAt))",
                        ]
                    )
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
        lastAcceptedInput = nil
        state = .loading(hosts)
    }

    func setIdle(hosts: [DockHostViewModel]) {
        lastAcceptedInput = nil
        state = .idle(hosts)
    }

    func setConfigurationError(_ message: String) {
        lastAcceptedInput = nil
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
                filters: options.filters,
                expansionState: options.expansionState
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
                filters: options.filters,
                expansionState: options.expansionState
            )
        )
    }

    func setFilters(_ filters: DockFilterState) {
        updateOptions(
            DockProjectionOptions(
                lens: options.lens,
                searchText: searchText,
                filters: filters,
                expansionState: options.expansionState
            ),
            syncSearchText: false
        )
    }

    func setPinnedCollapsed(_ isCollapsed: Bool) {
        var expansionState = options.expansionState
        expansionState.isPinnedCollapsed = isCollapsed
        updateExpansionState(expansionState)
    }

    func setGroupCollapsed(
        kind: DockProjectionGroupKind,
        id: String,
        isCollapsed: Bool
    ) {
        var expansionState = options.expansionState
        switch kind {
        case .host:
            if isCollapsed {
                expansionState.collapsedHostGroupIDs.insert(id)
            } else {
                expansionState.collapsedHostGroupIDs.remove(id)
            }
        case .branch:
            if isCollapsed {
                expansionState.collapsedBranchGroupIDs.insert(id)
            } else {
                expansionState.collapsedBranchGroupIDs.remove(id)
            }
        }
        updateExpansionState(expansionState)
    }

    private func updateExpansionState(_ expansionState: DockProjectionExpansionState) {
        updateOptions(
            DockProjectionOptions(
                lens: options.lens,
                searchText: options.searchText,
                filters: options.filters,
                expansionState: expansionState
            ),
            syncSearchText: false
        )
    }

    func updateOptions(_ options: DockProjectionOptions, syncSearchText: Bool = true) {
        let previousOptions = self.options
        self.options = options
        if syncSearchText {
            searchText = options.searchText
        }
        guard previousOptions != options else {
            return
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
        let options = self.options
        let inputKey = DockRenderInputKey(snapshot: snapshot, options: options)
        guard inputKey != lastAcceptedInput else {
            PerformanceProbe.event(
                "dock.render.noop_input",
                fields: [
                    "rows": "\(snapshot.rows.count)",
                    "hosts": "\(snapshot.hosts.count)",
                    "lens": options.lens.rawValue,
                    "search": options.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                    "filters": "\(options.filters.activeFilterCount)",
                    "partial": "\(snapshot.isPartial)",
                ]
            )
            return
        }
        lastAcceptedInput = inputKey
        latestRevision = latestRevision.next()
        let revision = latestRevision
        let now = self.now
        let coalescer = self.coalescer
        let queuedAt = Date()
        PerformanceProbe.event(
            "dock.render.enqueue",
            fields: [
                "revision": "\(revision.rawValue)",
                "rows": "\(snapshot.rows.count)",
                "hosts": "\(snapshot.hosts.count)",
                "lens": options.lens.rawValue,
                "search": options.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                "filters": "\(options.filters.activeFilterCount)",
                "partial": "\(snapshot.isPartial)",
            ]
        )
        if snapshot.rows.count > CodexDockConstants.Rendering.maxDockRowsPerMainPublish {
            DockLog.rendering.warning("dock render input exceeds main publish row budget rows=\(snapshot.rows.count, privacy: .public) budget=\(CodexDockConstants.Rendering.maxDockRowsPerMainPublish, privacy: .public)")
        }

        Task.detached(priority: .userInitiated) {
            let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.dockRenderProject)
            defer {
                DockSignpost.rendering.endInterval(RenderSignpostName.dockRenderProject, signpostState)
            }
            let renderStartedAt = Date()
            let renderSnapshot = DockRenderProjector(now: now).render(
                snapshot: snapshot,
                options: options,
                revision: revision
            )
            PerformanceProbe.event(
                "dock.render.detached_finished",
                fields: [
                    "revision": "\(revision.rawValue)",
                    "rows": "\(snapshot.rows.count)",
                    "queue_delay_ms": "\(PerformanceProbe.milliseconds(since: queuedAt, now: renderStartedAt))",
                    "render_ms": "\(PerformanceProbe.milliseconds(since: renderStartedAt))",
                ]
            )
            await coalescer.submit(renderSnapshot, revision: revision)
        }
    }
}

private struct DockRenderInputKey: Equatable, Sendable {
    let snapshot: DockSnapshot
    let options: DockProjectionOptions
}
