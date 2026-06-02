import Foundation

public struct HostConnectionTestResult: Equatable, Sendable {
    public let rowCount: Int

    public init(rowCount: Int) {
        self.rowCount = rowCount
    }
}

public protocol HostConnectionTesting: Sendable {
    func testConnection(to host: DockHostConfiguration) async throws -> HostConnectionTestResult
}

public struct CardStreamHostConnectionTester: HostConnectionTesting {
    private let streamClient: any ThreadCardStreamConnecting

    public init(streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient()) {
        self.streamClient = streamClient
    }

    public func testConnection(to host: DockHostConfiguration) async throws -> HostConnectionTestResult {
        var connection: (any ThreadCardStreamConnection)?
        do {
            connection = try await streamClient.connect(to: host)
            let snapshot = try await connection?.subscribe()
            await connection?.close()
            return HostConnectionTestResult(
                rowCount: snapshot?.totalRows ?? snapshot?.rows?.count ?? 0
            )
        } catch {
            await connection?.close()
            throw mapFailure(error)
        }
    }

    private func mapFailure(_ error: Error) -> DockRequestFailure {
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
