import XCTest
@testable import CodexDock

final class ThreadListMappingTests: XCTestCase {
    func testThreadListResponseDecodesFixturePayload() throws {
        let response = try decodeThreadListResponse(
            """
            {
              "data": [
                {
                  "id": "thread-1",
                  "sessionId": "session-1",
                  "forkedFromId": null,
                  "preview": "Build the Dock",
                  "ephemeral": false,
                  "modelProvider": "openai",
                  "createdAt": 1790000000,
                  "updatedAt": 1790000010,
                  "status": {
                    "type": "active",
                    "activeFlags": ["waitingOnUserInput"]
                  },
                  "path": "/Users/aelaguiz/.codex/sessions/thread-1.jsonl",
                  "cwd": "/Users/aelaguiz/workspace/codex-client",
                  "cliVersion": "0.135.0-alpha.2",
                  "source": "cli",
                  "threadSource": "user",
                  "agentNickname": null,
                  "agentRole": null,
                  "gitInfo": {
                    "sha": "abc123",
                    "branch": "main",
                    "originUrl": "git@github.com:aelaguiz/codex-client.git"
                  },
                  "name": "Codex Dock Phase 2",
                  "turns": []
                }
              ],
              "nextCursor": null,
              "backwardsCursor": "cursor-1"
            }
            """
        )

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "thread-1")
        XCTAssertEqual(response.data[0].status, .active(activeFlags: [.waitingOnUserInput]))
        XCTAssertEqual(response.backwardsCursor, "cursor-1")
    }

    func testMapsCompleteThreadToHostScopedSummary() {
        let response = ThreadListResponseDTO(
            data: [
                ThreadDTO(
                    id: "thread-1",
                    sessionId: "session-1",
                    preview: "Build the Dock\nwith real data",
                    createdAt: 1_790_000_000,
                    updatedAt: 1_790_000_010,
                    status: .active(activeFlags: [.waitingOnApproval]),
                    cwd: "/Users/aelaguiz/workspace/codex-client",
                    source: .string("cli"),
                    gitInfo: ThreadGitInfoDTO(
                        sha: "abc123",
                        branch: "main",
                        originUrl: "git@github.com:aelaguiz/codex-client.git"
                    ),
                    name: "Codex Dock Phase 2",
                    turns: []
                ),
            ]
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Amir-M5")

        XCTAssertEqual(result.failures, [])
        let summary = result.summaries[0]
        XCTAssertEqual(summary.id, HostScopedThreadID(hostID: "Amir-M5", threadID: "thread-1"))
        XCTAssertEqual(summary.backendSessionID, "session-1")
        XCTAssertEqual(summary.backendThreadID, "thread-1")
        XCTAssertEqual(summary.displayTitle, "Codex Dock Phase 2")
        XCTAssertEqual(summary.status, .active(activeFlags: [.waitingOnApproval]))
        XCTAssertTrue(summary.status.needsAttention)
        XCTAssertEqual(summary.repository, .known("codex-client"))
        XCTAssertEqual(summary.workingDirectory, .known("/Users/aelaguiz/workspace/codex-client"))
        XCTAssertEqual(summary.branch, .known("main"))
        XCTAssertEqual(summary.lastActivity.timeIntervalSince1970, 1_790_000_010)
        XCTAssertEqual(summary.shortEventSummary, .known("Build the Dock"))
    }

    func testSparsePayloadMapsUnknownOptionalMetadataWithoutDroppingThread() throws {
        let response = try decodeThreadListResponse(
            """
            {
              "data": [
                {
                  "id": "thread-2",
                  "sessionId": "session-2",
                  "preview": "",
                  "createdAt": 1790000100,
                  "updatedAt": 1790000105
                }
              ],
              "nextCursor": null,
              "backwardsCursor": null
            }
            """
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Home")

        XCTAssertEqual(result.failures, [])
        let summary = result.summaries[0]
        XCTAssertEqual(summary.id, HostScopedThreadID(hostID: "Home", threadID: "thread-2"))
        XCTAssertEqual(summary.backendSessionID, "session-2")
        XCTAssertEqual(summary.displayTitle, "Thread thread-2")
        XCTAssertEqual(summary.status, .unknown)
        XCTAssertEqual(summary.repository, .unknown)
        XCTAssertEqual(summary.workingDirectory, .unknown)
        XCTAssertEqual(summary.branch, .unknown)
        XCTAssertEqual(summary.lastActivity.timeIntervalSince1970, 1_790_000_105)
        XCTAssertEqual(summary.shortEventSummary, .unknown)
    }

    func testMalformedRowsProduceScopedMappingFailures() throws {
        let response = try decodeThreadListResponse(
            """
            {
              "data": [
                {
                  "sessionId": "missing-thread-id",
                  "preview": "bad",
                  "updatedAt": 1790000200
                },
                {
                  "id": "thread-3",
                  "sessionId": "session-3",
                  "preview": "still maps",
                  "updatedAt": 1790000205,
                  "status": { "type": "idle" }
                }
              ],
              "nextCursor": null,
              "backwardsCursor": null
            }
            """
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Amir-M5")

        XCTAssertEqual(result.summaries.map(\.backendThreadID), ["thread-3"])
        XCTAssertEqual(
            result.failures,
            [
                SessionSummaryMappingFailure(
                    index: 0,
                    backendThreadID: nil,
                    reason: "missing thread id"
                ),
            ]
        )
    }

    func testUnknownStatusAndActiveFlagsStayVisible() throws {
        let response = try decodeThreadListResponse(
            """
            {
              "data": [
                {
                  "id": "thread-4",
                  "sessionId": "session-4",
                  "preview": "new server state",
                  "updatedAt": 1790000300,
                  "status": {
                    "type": "active",
                    "activeFlags": ["waitingOnUserInput", "newFlag"]
                  }
                },
                {
                  "id": "thread-5",
                  "sessionId": "session-5",
                  "preview": "unknown status",
                  "updatedAt": 1790000301,
                  "status": { "type": "brandNewStatus" }
                }
              ],
              "nextCursor": null,
              "backwardsCursor": null
            }
            """
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Amir-M5")

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(
            result.summaries[0].status,
            .active(activeFlags: [.waitingOnUserInput, .unknown("newFlag")])
        )
        XCTAssertTrue(result.summaries[0].status.needsAttention)
        XCTAssertEqual(result.summaries[1].status, .unknown)
    }
}

private func decodeThreadListResponse(_ text: String) throws -> ThreadListResponseDTO {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try JSONDecoder().decode(ThreadListResponseDTO.self, from: data)
}
