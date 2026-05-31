import Foundation

struct ThreadCardHostLoadOutcome: Sendable {
    let host: DockHostConfiguration
    let result: Result<[DockThreadCardDTO], DockRequestFailure>
}

struct ThreadCardHostSnapshotLoader: Sendable {
    let streamClient: any ThreadCardStreamConnecting
    let expectedView: ThreadCardStreamView
    let operation: String

    func loadAll(hosts: [DockHostConfiguration]) async -> [ThreadCardHostLoadOutcome] {
        await withTaskGroup(of: ThreadCardHostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask {
                    await load(host: host)
                }
            }

            var outcomes: [ThreadCardHostLoadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { lhs, rhs in
                hostIndex(lhs.host.id, hosts: hosts) < hostIndex(rhs.host.id, hosts: hosts)
            }
        }
    }

    private func load(host: DockHostConfiguration) async -> ThreadCardHostLoadOutcome {
        let startedAt = Date()
        DockLog.archive.debug("\(self.operation, privacy: .public) card stream load started host_id=\(host.id, privacy: .public)")
        do {
            let connection = try await streamClient.connect(to: host)
            let cards: [DockThreadCardDTO]
            do {
                cards = try await ThreadCardStreamSnapshotCollector(expectedView: expectedView)
                    .collect(from: connection)
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
            DockLog.archive.debug("\(self.operation, privacy: .public) card stream load finished host_id=\(host.id, privacy: .public) rows=\(cards.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return ThreadCardHostLoadOutcome(host: host, result: .success(cards))
        } catch {
            DockLog.archive.warning("\(self.operation, privacy: .public) card stream load failed host_id=\(host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            return ThreadCardHostLoadOutcome(host: host, result: .failure(mapRequestFailure(error)))
        }
    }

    private func mapRequestFailure(_ error: Error) -> DockRequestFailure {
        if let failure = error as? DockRequestFailure {
            return failure
        }
        return .error(error.localizedDescription)
    }

    private func hostIndex(
        _ hostID: String,
        hosts: [DockHostConfiguration]
    ) -> Int {
        hosts.firstIndex { $0.id == hostID } ?? Int.max
    }
}
