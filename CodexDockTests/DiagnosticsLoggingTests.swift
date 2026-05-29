import XCTest
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
}
