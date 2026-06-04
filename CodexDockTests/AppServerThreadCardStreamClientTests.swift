import XCTest
@testable import CodexDock

final class AppServerThreadCardStreamClientTests: XCTestCase {
    func testDefaultCardStreamClientLetsProjectionLayerOwnReconnect() {
        let client = AppServerThreadCardStreamClient()

        XCTAssertEqual(client.defaultConnectionPolicy, .oneShot)
    }

    func testArchiveCardStreamClientAlsoLetsProjectionLayerOwnReconnect() {
        let client = AppServerThreadCardStreamClient(view: .archive)

        XCTAssertEqual(client.defaultConnectionPolicy, .oneShot)
    }

    func testInjectedClientFactoryDoesNotClaimDefaultReconnectPolicy() {
        let client = AppServerThreadCardStreamClient(makeClient: { endpoint in
            AppServerClient(webSocketURL: endpoint.webSocketURL, connectionPolicy: .liveDetail)
        })

        XCTAssertNil(client.defaultConnectionPolicy)
    }
}
