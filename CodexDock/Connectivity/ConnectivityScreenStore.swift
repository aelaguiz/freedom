import Combine
import Foundation

@MainActor
public final class ConnectivityScreenStore: ObservableObject {
    @Published public private(set) var snapshot: ConnectivityRenderSnapshot

    private let dataEngine: ConnectivityDataEngine?
    private let eventSink: ConnectivityEventSink?
    private let coalescer: RenderCoalescer<ConnectivityRenderSnapshot>
    private var eventTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    public init(
        registry: HostRegistry,
        eventSink: ConnectivityEventSink,
        coalescer: RenderCoalescer<ConnectivityRenderSnapshot> = RenderCoalescer<ConnectivityRenderSnapshot>(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let records = Dictionary(
            uniqueKeysWithValues: registry.hosts.map { host in
                let display = DockHostViewModel(host: host)
                return (
                    host.id,
                    ConnectivityHostRecord(
                        id: host.id,
                        displayName: display.displayName,
                        endpoint: display.endpoint,
                        phase: .unknown,
                        lastCheckedAt: nil,
                        lastSuccessAt: nil,
                        routeDiagnostics: []
                    )
                )
            }
        )
        self.snapshot = ConnectivityRenderProjector().render(
            records: records,
            hostOrder: registry.hosts.map(\.id),
            revision: .zero
        )
        self.dataEngine = ConnectivityDataEngine(registry: registry, now: now)
        self.eventSink = eventSink
        self.coalescer = coalescer
    }

    public init(configurationError error: Error) {
        self.snapshot = ConnectivityRenderSnapshot(
            revision: .zero,
            hosts: [],
            overallStatus: .configurationError(error.localizedDescription)
        )
        self.dataEngine = nil
        self.eventSink = nil
        self.coalescer = RenderCoalescer<ConnectivityRenderSnapshot>()
    }

    deinit {
        eventTask?.cancel()
        renderTask?.cancel()
    }

    public func start(mirroring appStore: AppConnectivityStore? = nil) {
        guard eventTask == nil, renderTask == nil else {
            return
        }
        guard let dataEngine, let eventSink else {
            appStore?.applyRuntimeSnapshot(snapshot)
            return
        }

        renderTask = Task { [weak self, coalescer, weak appStore] in
            let stream = await coalescer.stream()
            for await renderSnapshot in stream {
                await MainActor.run {
                    self?.snapshot = renderSnapshot
                    appStore?.applyRuntimeSnapshot(renderSnapshot)
                }
            }
        }

        eventTask = Task { [coalescer, dataEngine, eventSink] in
            let (stream, existingEvents) = await eventSink.makeStreamDrainingBacklog()
            for event in existingEvents {
                let renderSnapshot = await dataEngine.apply(event)
                await coalescer.submit(renderSnapshot, revision: renderSnapshot.revision)
            }
            for await event in stream {
                let renderSnapshot = await dataEngine.apply(event)
                await coalescer.submit(renderSnapshot, revision: renderSnapshot.revision)
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        renderTask?.cancel()
        renderTask = nil
    }

    public func configure(_ registry: HostRegistry) async {
        guard let dataEngine else {
            return
        }
        let renderSnapshot = await dataEngine.configure(registry)
        await coalescer.submit(renderSnapshot, revision: renderSnapshot.revision)
    }
}
