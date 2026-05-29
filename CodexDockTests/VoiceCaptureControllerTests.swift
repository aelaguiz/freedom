import XCTest
@testable import CodexDock

final class VoiceCaptureControllerTests: XCTestCase {
    func testRouteCategoryChangeDoesNotStopCapture() {
        XCTAssertFalse(
            VoiceCaptureSessionStopPolicy.shouldStopForRouteChange(.categoryChange)
        )
    }

    func testOldInputDeviceUnavailableStopsCapture() {
        XCTAssertTrue(
            VoiceCaptureSessionStopPolicy.shouldStopForRouteChange(.oldDeviceUnavailable)
        )
    }

    func testOtherRouteChangesDoNotStopCapture() {
        XCTAssertFalse(
            VoiceCaptureSessionStopPolicy.shouldStopForRouteChange(.other)
        )
    }

    func testInterruptionEndedDoesNotStopCapture() {
        XCTAssertFalse(
            VoiceCaptureSessionStopPolicy.shouldStopForInterruption(.ended)
        )
    }

    func testInterruptionStartAndUnknownInterruptionStopCapture() {
        XCTAssertTrue(
            VoiceCaptureSessionStopPolicy.shouldStopForInterruption(.began)
        )
        XCTAssertTrue(
            VoiceCaptureSessionStopPolicy.shouldStopForInterruption(.other)
        )
        XCTAssertTrue(
            VoiceCaptureSessionStopPolicy.shouldStopForInterruption(nil)
        )
    }
}
