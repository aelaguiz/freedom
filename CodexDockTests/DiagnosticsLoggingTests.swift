import Foundation
import XCTest

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CodexDock

final class DiagnosticsLoggingTests: XCTestCase {
    func testRedactionRemovesBearerAPIKeysAndLargeTokens() {
        let largeToken = String(repeating: "A", count: 128)
        let value = """
        Authorization: Bearer raw-bearer-token
        openAIAPIKey=sk-abcdefghijklmnopqrstuvwxyz123456
        audio=\(largeToken)
        """

        let redacted = DockLog.redacted(value)

        XCTAssertFalse(redacted.contains("raw-bearer-token"))
        XCTAssertFalse(redacted.contains("sk-abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(redacted.contains(largeToken))
        XCTAssertTrue(redacted.contains("Authorization=<redacted>"))
        XCTAssertTrue(redacted.contains("openAIAPIKey=<redacted>"))
        XCTAssertTrue(redacted.contains("<redacted-large-token>"))
    }

    func testEndpointRemovesCredentialsQueryAndFragment() throws {
        let url = try XCTUnwrap(
            URL(string: "ws://user:pass@127.0.0.1:4510/path?token=secret#frag")
        )

        XCTAssertEqual(DockLog.endpoint(url), "ws://127.0.0.1:4510/path")
    }

    func testRedactionTruncatesWithASCIISuffix() {
        let redacted = DockLog.redacted(String(repeating: "x", count: 20), maxLength: 10)

        XCTAssertEqual(redacted.count, 10)
        XCTAssertTrue(redacted.hasSuffix("..."))
    }

    func testObservabilityContractCoversAllCurrentAppServerMethods() {
        let expectedRoutes: Set<String> = [
            AppServerMethods.initialize,
            AppServerMethods.initialized,
            AppServerMethods.threadDetailRead,
            AppServerMethods.threadDetailSubscribe,
            AppServerMethods.threadDetailResync,
            AppServerMethods.threadDetailUpdate,
            AppServerMethods.threadArchive,
            AppServerMethods.threadUnarchive,
            AppServerMethods.dockSubscribe,
            AppServerMethods.dockUpdate,
            AppServerMethods.dockResync,
            AppServerMethods.archiveSubscribe,
            AppServerMethods.archiveUpdate,
            AppServerMethods.archiveResync,
            AppServerMethods.turnStart,
            AppServerMethods.turnSteer,
            AppServerMethods.turnInterrupt,
            AppServerMethods.audioTranscriptionStart,
            AppServerMethods.audioTranscriptionAppend,
            AppServerMethods.audioTranscriptionCommit,
            AppServerMethods.audioTranscriptionCancel,
            AppServerMethods.audioTranscriptionDelta,
            AppServerMethods.audioTranscriptionCompleted,
            AppServerMethods.audioTranscriptionFailed,
            AppServerMethods.audioTranscriptionCanceled,
            AppServerMethods.audioTranscriptionClosed,
        ]

        XCTAssertEqual(Set(ObservabilityContract.routes.map(\.name)), expectedRoutes)
        XCTAssertEqual(ObservabilityContract.config(for: AppServerMethods.turnStart).probeSafety, .passiveOnly)
        XCTAssertEqual(ObservabilityContract.config(for: AppServerMethods.threadArchive).probeSafety, .passiveOnly)
        XCTAssertEqual(ObservabilityContract.config(for: AppServerMethods.audioTranscriptionStart).probeSafety, .passiveOnly)
        XCTAssertFalse(ObservabilityContract.config(for: AppServerMethods.threadDetailRead).appCritical)
        XCTAssertTrue(ObservabilityContract.config(for: AppServerMethods.dockSubscribe).appCritical)
        XCTAssertTrue(ObservabilityContract.config(for: AppServerMethods.archiveSubscribe).appCritical)
    }

    func testRelayDiagnosticsClientDerivesSiblingDiagnosticURLs() throws {
        let endpoint = try DockRelayEndpoint(host: "home.fairy-salmon.ts.net", port: 4510)
        let client = RelayDiagnosticsClient()

        XCTAssertEqual(
            try client.diagnosticsURL(for: endpoint, path: "/routesz").absoluteString,
            "http://home.fairy-salmon.ts.net:4510/routesz"
        )
        XCTAssertEqual(
            try client.diagnosticsURL(for: endpoint, path: "syncz").absoluteString,
            "http://home.fairy-salmon.ts.net:4510/syncz"
        )
    }

    func testRelayDiagnosticsClientDecodesFractionalRelayTimestamps() async throws {
        let endpoint = try DockRelayEndpoint(host: "127.0.0.1", port: 4510)
        let routesURL = try RelayDiagnosticsClient().diagnosticsURL(for: endpoint, path: "/routesz")
        let payload = """
        {
          "ok": true,
          "routes": [
            {
              "configuredHostID": "127.0.0.1:4510",
              "relayHostID": "home",
              "route": "dock/subscribe",
              "routeStatus": "failed",
              "statusReasons": [
                {
                  "code": "failed:last-attempt",
                  "message": "last attempt failed",
                  "actual": "history",
                  "evidenceIDs": ["ev_1"]
                }
              ],
              "lastAttempt": {
                "operationID": "op_1",
                "at": "2026-05-30T12:00:00.123Z"
              },
              "lastSuccess": null,
              "lastFailure": {
                "operationID": "op_1",
                "at": "2026-05-30T12:00:00.123Z"
              },
              "appCritical": true,
              "appImpact": "app-critical"
            }
          ]
        }
        """.data(using: .utf8)!
        RelayDiagnosticsURLProtocol.responses = [
            routesURL: (statusCode: 200, data: payload),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayDiagnosticsURLProtocol.self]
        let client = RelayDiagnosticsClient(session: URLSession(configuration: configuration))

        let routes = try await client.fetchRoutes(for: endpoint)

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].route, AppServerMethods.dockSubscribe)
        XCTAssertEqual(routes[0].routeStatus, .failed)
        XCTAssertEqual(routes[0].lastAttemptAt, Date(timeIntervalSince1970: 1_780_142_400.123))
    }

    func testClientObservabilityBundleContainsRouteEvidenceAndOmissionList() async {
        let now = Date(timeIntervalSince1970: 1_780_142_400)
        let store = ClientObservabilityStore(persistenceDirectory: nil, now: { now })
        let context = AppServerRequestObservabilityContext(
            configuredHostID: "home.fairy-salmon.ts.net:4510",
            route: AppServerMethods.dockSubscribe,
            operationID: "op-dock-subscribe",
            traceID: "tr-dock-subscribe",
            store: store
        )

        await store.start(context)
        await store.finish(context, result: .failure(AppServerClientError.transport("dock provider offline")))
        let bundle = await store.diagnosticBundle(hosts: ["home.fairy-salmon.ts.net:4510"])

        XCTAssertEqual(bundle.schema, "codexdock.appBundle.v1")
        XCTAssertEqual(bundle.hosts, ["home.fairy-salmon.ts.net:4510"])
        XCTAssertEqual(bundle.routeDiagnostics.count, 1)
        XCTAssertEqual(bundle.routeDiagnostics[0].operationID, "op-dock-subscribe")
        XCTAssertEqual(bundle.routeDiagnostics[0].routeStatus, .failed)
        XCTAssertTrue(bundle.omitted.contains("prompts"))
        XCTAssertTrue(bundle.omitted.contains("transcripts"))
        XCTAssertTrue(bundle.omitted.contains("audio"))
        XCTAssertTrue(bundle.omitted.contains("full-jsonrpc-payloads"))
    }
}

private final class RelayDiagnosticsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: (statusCode: Int, data: Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = Self.responses[url],
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: RelayDiagnosticsURLProtocolError.missingResponse)
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum RelayDiagnosticsURLProtocolError: Error {
    case missingResponse
}
