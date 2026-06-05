import Combine
import Foundation

enum ThreadDetailScreenState: Equatable, Sendable {
    case idle(ThreadDetailHeader)
    case loading(ThreadDetailHeader)
    case loaded(ThreadDetailRenderSnapshot)
    case error(ThreadDetailHeader, String)
}

@MainActor
final class ThreadDetailScreenStore: ObservableObject {
    @Published private(set) var state: ThreadDetailScreenState
    @Published private(set) var options: ThreadDetailRenderOptions
    @Published private(set) var composer: ComposerState
    @Published private(set) var composerRenderState: ComposerRenderState

    private var coalescer: RenderCoalescer<ThreadDetailRenderSnapshot>
    private var renderTask: Task<Void, Never>?
    private var latestRevision = RenderRevision.zero
    private var latestSnapshot: ThreadDetailSnapshot?
    private var latestRequestCardPresentation = ThreadDetailRequestCardPresentation()

    init(
        header: ThreadDetailHeader,
        options: ThreadDetailRenderOptions = ThreadDetailRenderOptions(),
        coalescer: RenderCoalescer<ThreadDetailRenderSnapshot> = RenderCoalescer<ThreadDetailRenderSnapshot>()
    ) {
        self.state = .idle(header)
        self.options = options
        let composer = ComposerState()
        self.composer = composer
        self.composerRenderState = ComposerRenderState(composer: composer)
        self.coalescer = coalescer
    }

    deinit {
        renderTask?.cancel()
    }

    func start() {
        guard renderTask == nil else {
            return
        }

        let coalescer = RenderCoalescer<ThreadDetailRenderSnapshot>()
        self.coalescer = coalescer
        renderTask = Task { [weak self, coalescer] in
            let stream = await coalescer.stream()
            for await renderSnapshot in stream {
                await MainActor.run {
                    self?.state = .loaded(renderSnapshot)
                }
            }
        }

        if let latestSnapshot {
            publish(
                snapshot: latestSnapshot,
                requestCardPresentation: latestRequestCardPresentation
            )
        }
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
    }

    func setLoading(_ header: ThreadDetailHeader) {
        state = .loading(header)
    }

    func setError(header: ThreadDetailHeader, message: String) {
        state = .error(header, message)
    }

    func setComposer(_ composer: ComposerState) {
        self.composer = composer
        composerRenderState = ComposerRenderState(composer: composer)
    }

    func setFilter(_ filter: ThreadDetailMessageFilter) {
        updateOptions(
            ThreadDetailRenderOptions(
                filter: filter,
                visibleLimit: options.visibleLimit
            )
        )
    }

    func updateOptions(_ options: ThreadDetailRenderOptions) {
        self.options = options
        guard let latestSnapshot else {
            return
        }
        publish(
            snapshot: latestSnapshot,
            requestCardPresentation: latestRequestCardPresentation
        )
    }

    func publish(
        snapshot: ThreadDetailSnapshot,
        requestCardPresentation: ThreadDetailRequestCardPresentation = ThreadDetailRequestCardPresentation()
    ) {
        latestSnapshot = snapshot
        latestRequestCardPresentation = requestCardPresentation
        latestRevision = latestRevision.next()
        let revision = latestRevision
        let options = self.options
        let coalescer = self.coalescer

        Task.detached(priority: .userInitiated) {
            let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.threadRenderProject)
            defer {
                DockSignpost.rendering.endInterval(RenderSignpostName.threadRenderProject, signpostState)
            }
            let renderSnapshot = ThreadDetailRenderProjector().render(
                snapshot: snapshot,
                requestCardPresentation: requestCardPresentation,
                options: options,
                revision: revision
            )
            await coalescer.submit(renderSnapshot, revision: revision)
        }
    }
}
