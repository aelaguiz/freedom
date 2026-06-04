# Thread Detail Keyboard Dismissal Work Log - 2026-06-04

Last updated: 2026-06-04T14:51:39Z

## Objective

Fix the iOS UX bug where the thread-detail keyboard stays up after the user
sends a message or enters the composer. The final fix must be canonical,
plan-audited before implementation, simulator-tested, reviewed with the
thermo-nuclear code-quality bar, committed, and pushed.

## Online UX Research

Sources checked:

- Apple Human Interface Guidelines, Text fields:
  https://developer.apple.com/design/human-interface-guidelines/text-fields/
- Apple SwiftUI `FocusState` documentation:
  https://developer.apple.com/documentation/SwiftUI/FocusState
- Apple SwiftUI `scrollDismissesKeyboard(_:)` documentation:
  https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard%28_%3A%29
- Apple UIKit `textFieldShouldReturn(_:)` documentation:
  https://developer.apple.com/documentation/uikit/uitextfielddelegate/textfieldshouldreturn%28_%3A%29

Research summary:

- Apple treats keyboard behavior as field focus behavior. In SwiftUI, the
  canonical programmatic path is an explicit `@FocusState`; clearing that focus
  removes focus from the bound field and dismisses the keyboard.
- Scrollable content should have an intentional keyboard-dismissal policy.
  SwiftUI exposes that as `scrollDismissesKeyboard(_:)`.
- UIKit's older equivalent is the same concept in imperative form:
  the active field resigns first responder when the user completes input.
- The user expectation for a chat/composer surface is not "keyboard remains
  forever." Sending a message completes that editing transaction, so the
  composer should resign focus. Starting voice dictation is also a switch of
  input mode, so the text keyboard should resign before capture starts.

## Code Areas Read

- `CodexDock/Features/Session/SessionDetailView.swift`
- `CodexDock/Features/Session/ComposerView.swift`
- `CodexDock/Features/Session/ThreadMessageListView.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/State/ThreadDetailStore+Voice.swift`
- `CodexDock/Automation/AutomationID.swift`
- `CodexDockUITests/CodexDockUserMessageLatencyUITests.swift`
- `CodexDockUITests/DisplayedUICaptureSupport.swift`
- `Makefile`
- `project.yml`

## Findings

### Finding 1 - Composer has no focus owner

`ComposerView` renders the message `TextField` but does not bind it to a
`@FocusState`. The view can update draft text and send the draft, but it never
owns or clears text focus. That means tapping the field lets SwiftUI/the system
own the keyboard implicitly, and sending only clears the draft. It does not
tell the field to resign focus.

Consequence: after a send, the composer can be empty and non-sending while the
keyboard remains up.

### Finding 2 - Send action is data-only, not edit-lifecycle complete

`ThreadDetailStore.sendDraft()` now correctly clears the draft immediately and
sends in the background. That is data-state behavior. It should not also own UI
focus. The missing piece belongs in `ComposerView`: the send control should
end editing before it dispatches the store command.

Consequence: the store is doing the right data work, but the view never closes
the input lifecycle.

### Finding 3 - Voice controls do not dismiss text input first

The hold and tap dictation controls start/finalize voice capture without
clearing composer text focus. If the user tapped the message field first, then
uses voice, the keyboard can stay visible even though the user has moved from
typing to dictation.

Consequence: voice and keyboard compete as simultaneous input modes.

### Finding 4 - Thread detail scroll view has no explicit keyboard policy

`SessionDetailView` owns the top-level thread-detail `ScrollView`, but it does
not declare `scrollDismissesKeyboard`. SwiftUI has defaults, but the thread
detail screen should make the intended behavior explicit because this screen is
mostly scrollable transcript content plus input controls.

Consequence: drag-to-dismiss is not an obvious, audited part of the screen
contract.

### Finding 5 - Request-card input is an adjacent same-screen side path

`ThreadMessageListView` has request-card `TextField("Answer", ...)` controls
and request send buttons. They are not the reported composer bug, but they live
on the same thread-detail screen and have the same "field + send button"
shape. Fixing only the composer would leave a same-screen text-input side path
with the older implicit-focus behavior.

Consequence: the architecture would stay split inside the same screen.

### Finding 6 - Existing simulator proof can be extended

`CodexDockUITests/CodexDockUserMessageLatencyUITests.swift` already opens a
controlled thread, taps the composer, types text, taps send, and verifies
non-blocking send behavior. This is the exact highest-risk path for the
keyboard bug. The proof can assert that composer focus is false after send and
that the software keyboard is not visible after the send transaction.

Consequence: no new proof framework is needed. The existing controlled
simulator proof can widen to cover keyboard dismissal.

## Working Diagnosis

This is not a relay, Codex, or send-command bug. It is a missing UI focus
contract. The data command path now completes quickly, but the view does not
declare what "send" means for text editing focus. The canonical fix is to make
thread-detail text focus explicit and clear it at the user-action boundary.

## Implemented Fix

- `ComposerView` now owns explicit SwiftUI focus for the message field with
  `@FocusState`.
- Composer send button and Return-submit both call the same local submit
  helper. That helper clears focus first, then submits.
- Hold-to-dictate and tap-to-dictate both clear composer focus before starting
  or toggling voice input.
- `SessionDetailView` now declares iOS
  `scrollDismissesKeyboard(.interactively)` on the thread-detail scroll view.
- Request-card answer fields now own local focus and clear that focus before
  submitting the request-card response.
- `ThreadDetailStore` now exposes `sendDraftInBackground()` so the local
  draft clear, pending outbound insert, and publish happen synchronously from
  the button action while network delivery still runs in the background.
- The user-message latency UI proof now records composer focus, keyboard
  visibility, composer clear, pending row, and canonical row timings.
- `Makefile` now gives the user-message latency fixture its own
  `SIM_UI_USER_MESSAGE_WAIT_TIMEOUT_MS` lifetime so a slow simulator launch
  cannot outlive the fake relay/app-server before the UI test sends.

## Verification

Focused Swift test:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

Result: pass. Executed 64 tests with 0 failures.

Simulator proof:

```bash
rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'
```

Result: pass. Artifact:
`/tmp/codex-client/sim-ui-user-message-20260604T145112Z/user-message-latency.json`.

Measured proof facts from that run:

- Composer focus cleared in 589 ms.
- Software keyboard was visible before send and dismissed in 589 ms.
- Composer local state cleared in 589 ms.
- Pending outbound row appeared in 589 ms.
- Canonical server row appeared in 2800 ms with a deliberate 2500 ms upstream
  acknowledgement delay.
- Final composer automation value:
  `can-edit=true; can-send=false; sending=false; message-focused=false; voice=Dictate`.

## Thermo-Nuclear Review Outcome

Review was run against the implementation diff before commit. Findings and
fixes:

- Avoided widening the old async `sendDraft()` API. Kept `sendDraft()` as the
  compatibility wrapper and added the explicit synchronous
  `sendDraftInBackground()` path for the UI.
- Removed heavier one-field focus models. Composer and request-card inputs now
  use simple Boolean `@FocusState` bindings.
- Extracted the multi-condition simulator timing loop into
  `observeUserMessageProofBudget(...)` so the UI test body stays readable.
- Added `SIM_UI_USER_MESSAGE_WAIT_TIMEOUT_MS` after a failed run proved the
  user-message fixture could time out before a slow simulator test finished
  launching. This is a proof-harness fix, not a product behavior change.

Post-review file sizes stayed below the 1000-line review threshold for touched
source/test files.
