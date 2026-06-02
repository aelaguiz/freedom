import Foundation
import OSLog

@MainActor
protocol ThreadCardStreamLifecycleDelegate: AnyObject {
    func cardStreamLifecycleMarkChecking(host: DockHostConfiguration) async
    func cardStreamLifecycleMarkFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) async
    func cardStreamLifecycleApplySnapshot(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async -> ThreadCardTableApplyResult
    func cardStreamLifecycleApplyUpdate(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async -> ThreadCardTableApplyResult
    func cardStreamLifecycleRowCount(for host: DockHostConfiguration) async -> Int
    func cardStreamLifecyclePublishSnapshot() async
    func cardStreamLifecycleMigrateMetadataHostAliases() async
}

@MainActor
final class ThreadCardStreamLifecycle {
    private let view: ThreadCardStreamView
    private let streamClient: any ThreadCardStreamConnecting
    private let streamReconnectDelay: Duration
    private let streamHeartbeatTimeout: Duration
    private let logger: Logger
    private let logName: String
    private weak var delegate: (any ThreadCardStreamLifecycleDelegate)?

    private var streamConnections: [String: any ThreadCardStreamConnection] = [:]
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var streamHeartbeatTasks: [String: Task<Void, Never>] = [:]
    private var streamHeartbeatTokens: [String: UUID] = [:]

    init(
        view: ThreadCardStreamView,
        streamClient: any ThreadCardStreamConnecting,
        streamReconnectDelay: Duration,
        streamHeartbeatTimeout: Duration,
        logger: Logger,
        logName: String,
        delegate: any ThreadCardStreamLifecycleDelegate
    ) {
        self.view = view
        self.streamClient = streamClient
        self.streamReconnectDelay = streamReconnectDelay
        self.streamHeartbeatTimeout = streamHeartbeatTimeout
        self.logger = logger
        self.logName = logName
        self.delegate = delegate
    }

    deinit {
        streamTasks.values.forEach { $0.cancel() }
        streamHeartbeatTasks.values.forEach { $0.cancel() }
    }

    func synchronizeStreams(hosts: [DockHostConfiguration]) async {
        let validHostIDs = Set(hosts.map(\.id))
        for hostID in streamConnections.keys where !validHostIDs.contains(hostID) {
            streamTasks[hostID]?.cancel()
            streamTasks[hostID] = nil
            streamHeartbeatTasks[hostID]?.cancel()
            streamHeartbeatTasks[hostID] = nil
            streamHeartbeatTokens[hostID] = nil
            let connection = streamConnections.removeValue(forKey: hostID)
            await connection?.close()
        }

        for host in hosts {
            if let connection = streamConnections[host.id] {
                await resync(host: host, connection: connection)
            } else {
                await openStream(host: host)
            }
        }
    }

    func closeStreams() async {
        streamTasks.values.forEach { $0.cancel() }
        streamTasks = [:]
        streamHeartbeatTasks.values.forEach { $0.cancel() }
        streamHeartbeatTasks = [:]
        streamHeartbeatTokens = [:]
        let connections = streamConnections
        streamConnections = [:]
        for connection in connections.values {
            await connection.close()
        }
    }

    private func openStream(host: DockHostConfiguration) async {
        guard let delegate else {
            return
        }

        await delegate.cardStreamLifecycleMarkChecking(host: host)
        await delegate.cardStreamLifecyclePublishSnapshot()
        var openedConnection: (any ThreadCardStreamConnection)?
        do {
            let connection = try await streamClient.connect(to: host)
            openedConnection = connection
            streamConnections[host.id] = connection
            let snapshot = try await connection.subscribe()
            try await applySubscribedSnapshot(snapshot, host: host, connection: connection)
            recordStreamActivity(host: host, connection: connection)
            startUpdateTask(host: host, connection: connection)
            await delegate.cardStreamLifecycleMigrateMetadataHostAliases()
            await delegate.cardStreamLifecyclePublishSnapshot()
        } catch {
            streamTasks[host.id]?.cancel()
            streamTasks[host.id] = nil
            streamHeartbeatTasks[host.id]?.cancel()
            streamHeartbeatTasks[host.id] = nil
            streamHeartbeatTokens[host.id] = nil
            streamConnections[host.id] = nil
            await openedConnection?.close()
            logger.warning("\(self.logName, privacy: .public) stream open failed view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            await delegate.cardStreamLifecycleMarkFailure(Self.mapRequestFailure(error), host: host)
            await delegate.cardStreamLifecyclePublishSnapshot()
        }
    }

    private func resync(host: DockHostConfiguration, connection: any ThreadCardStreamConnection) async {
        guard let delegate else {
            return
        }

        do {
            let snapshot = try await connection.resync()
            try await applyResyncSnapshot(snapshot, host: host)
            await delegate.cardStreamLifecycleMigrateMetadataHostAliases()
            await delegate.cardStreamLifecyclePublishSnapshot()
            let rowCount = await delegate.cardStreamLifecycleRowCount(for: host)
            logger.notice("\(self.logName, privacy: .public) stream resync finished view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) rows=\(rowCount, privacy: .public)")
        } catch {
            logger.warning("\(self.logName, privacy: .public) stream resync failed view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            await delegate.cardStreamLifecycleMarkFailure(Self.mapRequestFailure(error), host: host)
            await delegate.cardStreamLifecyclePublishSnapshot()
        }
    }

    private func startUpdateTask(host: DockHostConfiguration, connection: any ThreadCardStreamConnection) {
        streamTasks[host.id]?.cancel()
        streamTasks[host.id] = Task { [weak self, host, connection] in
            do {
                for try await update in connection.updates() {
                    await self?.handleStreamUpdate(update, host: host, connection: connection)
                }
                if !Task.isCancelled {
                    await self?.handleStreamFailure(
                        DockRequestFailure.offline("Relay stream closed"),
                        host: host,
                        connection: connection
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.handleStreamFailure(error, host: host, connection: connection)
            }
        }
    }

    private func recordStreamActivity(host: DockHostConfiguration, connection: any ThreadCardStreamConnection) {
        let token = UUID()
        streamHeartbeatTokens[host.id] = token
        streamHeartbeatTasks[host.id]?.cancel()
        streamHeartbeatTasks[host.id] = Task { [weak self, host, connection, token] in
            guard let self else {
                return
            }
            let timeout = streamHeartbeatTimeout
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self.handleHeartbeatTimeout(host: host, connection: connection, token: token)
        }
    }

    private func handleHeartbeatTimeout(
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection,
        token: UUID
    ) async {
        guard streamHeartbeatTokens[host.id] == token else {
            return
        }
        logger.warning("\(self.logName, privacy: .public) stream heartbeat timed out view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public)")
        await handleStreamFailure(
            DockRequestFailure.offline("Relay stream heartbeat timed out"),
            host: host,
            connection: connection
        )
    }

    private func handleStreamUpdate(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async {
        guard let delegate else {
            return
        }

        recordStreamActivity(host: host, connection: connection)
        let result = await delegate.cardStreamLifecycleApplyUpdate(update, host: host)
        if case .needsResync(let reason) = result {
            logger.warning("\(self.logName, privacy: .public) stream resync needed view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public)")
            await resync(host: host, connection: connection)
        } else {
            await delegate.cardStreamLifecycleMigrateMetadataHostAliases()
            await delegate.cardStreamLifecyclePublishSnapshot()
            let rowCount = await delegate.cardStreamLifecycleRowCount(for: host)
            logger.info("\(self.logName, privacy: .public) stream update applied view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public) rows=\(rowCount, privacy: .public)")
            let freshness = update.freshness
            if freshness.status != .fresh,
               rowCount > 0 {
                logger.notice("\(self.logName, privacy: .public) stream rows retained view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) freshness=\(freshness.status.rawValue, privacy: .public) rows=\(rowCount, privacy: .public)")
            }
        }
    }

    private func applySubscribedSnapshot(
        _ snapshot: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async throws {
        guard let delegate else {
            return
        }

        switch await delegate.cardStreamLifecycleApplySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            logger.warning("\(self.logName, privacy: .public) stream subscribe snapshot rejected view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) seq=\(snapshot.seq, privacy: .public)")
            let resynced = try await connection.resync()
            try await applyResyncSnapshot(resynced, host: host)
        }
    }

    private func applyResyncSnapshot(
        _ snapshot: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async throws {
        guard let delegate else {
            return
        }

        switch await delegate.cardStreamLifecycleApplySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            throw DockRequestFailure.error("\(logName.capitalized) stream resync returned incompatible data (\(reason.rawValue)).")
        }
    }

    private func handleStreamFailure(
        _ error: Error,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async {
        guard streamConnections[host.id] != nil else {
            return
        }
        guard let delegate else {
            return
        }

        logger.warning("\(self.logName, privacy: .public) stream update failed view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        streamHeartbeatTasks[host.id]?.cancel()
        streamHeartbeatTasks[host.id] = nil
        streamHeartbeatTokens[host.id] = nil
        streamConnections[host.id] = nil
        streamTasks[host.id] = nil
        await connection.close()
        await delegate.cardStreamLifecycleMarkFailure(Self.mapRequestFailure(error), host: host)
        await delegate.cardStreamLifecyclePublishSnapshot()
        let rowCount = await delegate.cardStreamLifecycleRowCount(for: host)
        if rowCount > 0 {
            logger.notice("\(self.logName, privacy: .public) stream rows retained view=\(self.view.rawValue, privacy: .public) host_id=\(host.id, privacy: .public) freshness=offline rows=\(rowCount, privacy: .public)")
        }
        scheduleReconnect(host: host)
    }

    private func scheduleReconnect(host: DockHostConfiguration) {
        streamTasks[host.id] = Task { [weak self, host] in
            do {
                try await Task.sleep(for: self?.streamReconnectDelay ?? CodexDockConstants.Dock.autoRefreshInterval)
            } catch {
                return
            }
            await self?.openStream(host: host)
        }
    }

    private nonisolated static func mapRequestFailure(_ error: Error) -> DockRequestFailure {
        if let failure = error as? DockRequestFailure {
            return failure
        }
        if let clientError = error as? AppServerClientError {
            switch clientError {
            case .disconnected, .notConnected, .requestTimedOut, .transport:
                return .offline(clientError.localizedDescription)
            case .duplicateRequestID,
                 .malformedMessage,
                 .requestCancelled,
                 .responseDecoding,
                 .server,
                 .unexpectedServerRequest,
                 .unmatchedResponse:
                return .error(clientError.localizedDescription)
            }
        }
        return .error(error.localizedDescription)
    }
}
