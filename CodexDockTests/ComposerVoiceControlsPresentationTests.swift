import XCTest
@testable import CodexDock

final class ComposerVoiceControlsPresentationTests: XCTestCase {
    func testIdleVoiceControlsExposeHoldAndTapEntryPoints() {
        let presentation = ComposerVoiceControlsPresentation(composer: ComposerState())

        XCTAssertEqual(presentation.holdAccessibilityLabel, "Hold to dictate")
        XCTAssertEqual(
            presentation.holdAccessibilityHint,
            "Press and hold to stream dictation. Release to finalize."
        )
        XCTAssertEqual(presentation.tapAccessibilityLabel, "Start dictation")
        XCTAssertEqual(
            presentation.tapAccessibilityHint,
            "Tap once to start dictation and tap again to finalize."
        )
        XCTAssertFalse(presentation.holdDisabled)
        XCTAssertFalse(presentation.tapDisabled)
        XCTAssertNil(presentation.statusText)
    }

    func testTapVoiceControlsExposeStopStateAndDisableHoldPath() {
        let presentation = ComposerVoiceControlsPresentation(
            composer: ComposerState(
                voice: ComposerVoiceState(
                    phase: .streaming,
                    interactionMode: .tap
                )
            )
        )

        XCTAssertEqual(presentation.tapAccessibilityLabel, "Stop dictation")
        XCTAssertEqual(presentation.tapIcon, "stop.circle.fill")
        XCTAssertEqual(presentation.statusText, "Listening. Tap stop to finalize.")
        XCTAssertTrue(presentation.holdDisabled)
        XCTAssertFalse(presentation.tapDisabled)
    }

    func testHoldVoiceControlsExposeReleaseStateAndDisableTapPath() {
        let presentation = ComposerVoiceControlsPresentation(
            composer: ComposerState(
                voice: ComposerVoiceState(
                    phase: .streaming,
                    interactionMode: .hold
                )
            )
        )

        XCTAssertEqual(presentation.tapAccessibilityLabel, "Start dictation")
        XCTAssertEqual(presentation.statusText, "Listening. Release to finalize.")
        XCTAssertFalse(presentation.holdDisabled)
        XCTAssertTrue(presentation.tapDisabled)
    }

    func testFinalizingDisablesBothVoiceEntryPoints() {
        for interactionMode in [ComposerVoiceInteractionMode.hold, .tap] {
            let presentation = ComposerVoiceControlsPresentation(
                composer: ComposerState(
                    voice: ComposerVoiceState(
                        phase: .finalizing,
                        interactionMode: interactionMode
                    )
                )
            )

            XCTAssertEqual(presentation.statusText, "Finalizing")
            XCTAssertTrue(presentation.holdDisabled)
            XCTAssertTrue(presentation.tapDisabled)
        }
    }
}
