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
              "backwardsCursor": "cursor-1",
              "liveOverlay": {
                "ok": false,
                "state": "disabled",
                "ageMs": null
              }
            }
            """
        )

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "thread-1")
        XCTAssertEqual(response.data[0].status, .active(activeFlags: [.waitingOnUserInput]))
        XCTAssertEqual(response.backwardsCursor, "cursor-1")
        XCTAssertEqual(response.liveOverlay?.degradedMessage, "Live status disabled")
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
        XCTAssertEqual(summary.origin.kind, .humanInteractive)
        XCTAssertEqual(summary.origin.humanSubtype, .cli)
        XCTAssertEqual(summary.origin.evidence.sourceKind, .cli)
    }

    func testMapsLatestMeaningfulTurnTextToShortEventSummary() {
        let response = ThreadListResponseDTO(
            data: [
                ThreadDTO(
                    id: "thread-latest",
                    sessionId: "session-latest",
                    preview: "Original opening prompt",
                    createdAt: 1_790_000_000,
                    updatedAt: 1_790_000_030,
                    status: .idle,
                    cwd: "/Users/aelaguiz/workspace/codex-client",
                    source: .string("cli"),
                    name: "Stable thread title",
                    turns: [
                        .object([
                            "id": .string("turn-old"),
                            "startedAt": .integer(1_790_000_010),
                            "items": .array([
                                .object([
                                    "id": .string("old-user"),
                                    "type": .string("userMessage"),
                                    "content": .array([
                                        .object(["text": .string("Original opening prompt")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                        .object([
                            "id": .string("turn-new"),
                            "startedAt": .integer(1_790_000_020),
                            "items": .array([
                                .object([
                                    "id": .string("new-agent"),
                                    "type": .string("agentMessage"),
                                    "text": .string("Latest agent update"),
                                ]),
                                .object([
                                    "id": .string("new-command"),
                                    "type": .string("commandExecution"),
                                    "command": .array([.string("rtk"), .string("swift"), .string("test")]),
                                    "aggregatedOutput": .string("Passed"),
                                ]),
                                .object([
                                    "id": .string("new-reasoning"),
                                    "type": .string("reasoning"),
                                    "summary": .array([
                                        .object(["text": .string("Internal reasoning should stay out of row summaries")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]
                ),
            ]
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Amir-M5")

        XCTAssertEqual(result.failures, [])
        let summary = result.summaries[0]
        XCTAssertEqual(summary.displayTitle, "Stable thread title")
        XCTAssertEqual(summary.shortEventSummary, .known("Latest agent update"))
    }

    func testMapsRelayLatestSummaryWithoutListTurnsToShortEventSummary() {
        let response = ThreadListResponseDTO(
            data: [
                ThreadDTO(
                    id: "thread-latest-summary",
                    sessionId: "session-latest-summary",
                    preview: "Original opening prompt",
                    createdAt: 1_790_000_000,
                    updatedAt: 1_790_000_030,
                    status: .idle,
                    cwd: "/Users/aelaguiz/workspace/codex-client",
                    source: .string("cli"),
                    name: "Stable thread title",
                    latestSummary: "Latest useful message from relay",
                    turns: []
                ),
            ]
        )

        let result = SessionSummaryMapper.map(response: response, hostID: "Amir-M5")

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries[0].shortEventSummary, .known("Latest useful message from relay"))
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
        XCTAssertEqual(summary.origin.kind, .unknown)
        XCTAssertNil(summary.origin.evidence.sourceKind)
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

    func testMapsExecAsAutomationEvenWhenThreadSourceIsUser() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(
                    id: "thread-exec",
                    source: .string("exec"),
                    threadSource: "user"
                )
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries[0].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[0].origin.automationSubtype, .exec)
        XCTAssertEqual(result.summaries[0].origin.evidence.sourceKind, .exec)
        XCTAssertEqual(result.summaries[0].origin.evidence.threadSource, "user")
    }

    func testMapsAppServerAndMCPAsAutomation() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(id: "thread-app-server", source: .string("app_server")),
                makeThread(id: "thread-mcp", source: .object(["type": .string("mcp")]))
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries[0].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[0].origin.automationSubtype, .appServer)
        XCTAssertEqual(result.summaries[0].origin.evidence.sourceKind, .appServer)
        XCTAssertEqual(result.summaries[1].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[1].origin.automationSubtype, .appServer)
        XCTAssertEqual(result.summaries[1].origin.evidence.sourceKind, .appServer)
    }

    func testMapsSubAgentObjectAndRoleEvidenceAsAutomation() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(
                    id: "thread-review",
                    source: .object(["subAgent": .string("review")])
                ),
                makeThread(
                    id: "thread-role",
                    source: nil,
                    threadSource: "subagent",
                    agentNickname: "reviewer",
                    agentRole: "code_review"
                ),
                makeThread(
                    id: "thread-spawn",
                    source: .object([
                        "subAgent": .object([
                            "thread_spawn": .object([:])
                        ])
                    ])
                )
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries[0].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[0].origin.automationSubtype, .subAgentReview)
        XCTAssertEqual(result.summaries[0].origin.evidence.sourceKind, .subAgentReview)
        XCTAssertEqual(result.summaries[1].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[1].origin.automationSubtype, .subAgentOther)
        XCTAssertEqual(result.summaries[1].origin.evidence.agentNickname, "reviewer")
        XCTAssertEqual(result.summaries[1].origin.evidence.agentRole, "code_review")
        XCTAssertEqual(result.summaries[2].origin.kind, .agentOrAutomation)
        XCTAssertEqual(result.summaries[2].origin.automationSubtype, .subAgentThreadSpawn)
        XCTAssertEqual(result.summaries[2].origin.evidence.sourceKind, .subAgentThreadSpawn)
        XCTAssertEqual(
            result.summaries[2].origin.evidence.rawSource,
            .object([
                "subAgent": .object([
                    "thread_spawn": .object([:])
                ])
            ])
        )
    }

    func testMapsKnownInteractiveCustomSourcesAsHuman() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(id: "thread-atlas", source: .string("atlas")),
                makeThread(id: "thread-chatgpt", source: .string("chatgpt"))
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries.map(\.origin.kind), [.humanInteractive, .humanInteractive])
        XCTAssertEqual(result.summaries[0].origin.humanSubtype, .customInteractive("atlas"))
        XCTAssertEqual(result.summaries[1].origin.humanSubtype, .customInteractive("chatgpt"))
    }

    func testMapsUnknownSourceAsUnknown() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(id: "thread-unknown", source: .string("unknown")),
                makeThread(id: "thread-future", source: .string("futureSource"))
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries.map(\.origin.kind), [.unknown, .unknown])
        XCTAssertEqual(result.summaries[0].origin.evidence.sourceKind, .unknown)
        XCTAssertEqual(result.summaries[1].origin.evidence.sourceKind, .unknown)
    }

    func testContradictorySourceEvidenceMapsUnknown() {
        let result = SessionSummaryMapper.map(
            response: ThreadListResponseDTO(data: [
                makeThread(
                    id: "thread-conflicting-source",
                    source: .object([
                        "cli": .object([:]),
                        "subAgent": .string("review")
                    ])
                ),
                makeThread(
                    id: "thread-conflicting-metadata",
                    source: .string("cli"),
                    agentNickname: "reviewer"
                ),
                makeThread(
                    id: "thread-conflicting-subagent-variants",
                    source: .object([
                        "subAgent": .array([
                            .string("review"),
                            .string("compact")
                        ])
                    ])
                )
            ]),
            hostID: "Amir-M5"
        )

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.summaries.map(\.origin.kind), [.unknown, .unknown, .unknown])
        XCTAssertEqual(result.summaries.map(\.origin.evidence.sourceKind), [.unknown, .unknown, .unknown])
    }
}

private func decodeThreadListResponse(_ text: String) throws -> ThreadListResponseDTO {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try JSONDecoder().decode(ThreadListResponseDTO.self, from: data)
}

private func makeThread(
    id: String,
    source: JSONValue?,
    threadSource: String? = nil,
    agentNickname: String? = nil,
    agentRole: String? = nil
) -> ThreadDTO {
    ThreadDTO(
        id: id,
        sessionId: "\(id)-session",
        preview: "Thread \(id)",
        createdAt: 1_790_000_000,
        updatedAt: 1_790_000_010,
        status: .idle,
        source: source,
        threadSource: threadSource,
        agentNickname: agentNickname,
        agentRole: agentRole,
        turns: []
    )
}
