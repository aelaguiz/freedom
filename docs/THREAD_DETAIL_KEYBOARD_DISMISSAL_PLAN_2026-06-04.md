# Thread Detail Keyboard Dismissal Plan - 2026-06-04

Last updated: 2026-06-04T14:51:39Z

Work log: `docs/THREAD_DETAIL_KEYBOARD_DISMISSAL_WORKLOG_2026-06-04.md`
Plan audit: `docs/THREAD_DETAIL_KEYBOARD_DISMISSAL_PLAN_2026-06-04_PLAN_AUDIT.md`

## North Star

On iOS, the thread-detail keyboard behaves like a normal chat composer:
typing focuses the composer, sending ends that edit transaction, voice capture
switches away from keyboard input, and scrolling the transcript can dismiss the
keyboard. The user can send a message and immediately continue reading or
interacting without the keyboard being stuck over the thread.

## Done-State Requirements

1. Composer send clears composer focus before dispatching the async send.
2. Composer Return/submit follows the same path as tapping the send button.
3. Starting hold-to-dictate or tap-to-dictate clears composer focus before
   voice capture starts.
4. The thread-detail transcript declares an explicit scroll keyboard-dismissal
   policy on iOS.
5. Request-card text input on the same screen clears its field focus when the
   user submits that request input.
6. The implementation stays local to thread-detail SwiftUI views. No global
   `UIApplication.endEditing`, responder-chain broadcast, app-wide keyboard
   observer, timer, or imperative UIKit escape hatch is introduced.
7. The existing simulator user-message proof verifies the keyboard/focus
   behavior for the controlled composer send path.
8. Focus state is exposed only as stable automation state needed for proof; no
   visible in-app instructional text is added.

## Non-Requirements

- Do not redesign the composer layout.
- Do not change relay, app-server, or command semantics.
- Do not auto-refocus the composer after send.
- Do not change physical-device config or service setup.
- Do not solve every text field across the whole app in this slice.

## Constraints

- Follow `Makefile`-owned simulator commands.
- Keep `.env` untouched.
- Keep the fix SwiftUI-first because these screens are SwiftUI views.
- Keep edits small and local unless simulator proof exposes a broader issue.
- Preserve current non-blocking send behavior from the prior user-message
  architecture work.

## Target Architecture

### Composer focus ownership

`ComposerView` owns a private focus flag:

```swift
@FocusState private var isMessageFieldFocused: Bool
```

The message `TextField` binds to that flag with
`.focused($isMessageFieldFocused)`. The view owns small local helpers:

- `dismissComposerKeyboard()`
- `submitDraftFromComposer()`
- `beginVoiceFromComposer()`
- `toggleTapVoiceFromComposer()`

Those helpers clear focus first, then run the existing async closures. This
keeps UI focus in the view and keeps data send in `ThreadDetailStore`.

### Return key path

The message field uses `.submitLabel(.send)` and `.onSubmit` to call the same
submit helper as the send button, gated by `composerRenderState.canSend`.

### Voice path

Both voice entry controls call the same focus-clear helper before starting or
toggling capture. Finishing hold capture does not need to refocus text input.

### Scroll dismissal

`SessionDetailView` applies `scrollDismissesKeyboard(.interactively)` on iOS to
the top-level transcript `ScrollView`. This makes drag-to-dismiss an explicit
screen contract.

### Request-card input convergence

`ThreadMessageCard` owns local request-input focus for its own `Answer` field.
Submitting through Return or the request send button clears that local focus
before invoking the existing request action callback.

## Implementation Steps

1. Update `ComposerView.swift`.
   - Add `@FocusState`.
   - Bind the message field to focus.
   - Add submit/voice helper methods.
   - Add `message-focused=<true|false>` to composer automation value.
2. Update `SessionDetailView.swift`.
   - Add iOS-only `.scrollDismissesKeyboard(.interactively)`.
3. Update `ThreadMessageListView.swift`.
   - Add local request-card field focus.
   - Clear focus on request input submit.
4. Update `CodexDockUserMessageLatencyUITests.swift`.
   - Capture post-send composer focus state.
   - Assert focus becomes false within the UI budget.
   - Record whether a software keyboard is visible after send.
5. Run focused tests.
   - `rtk swift test --filter ThreadDetailStoreTests`
   - `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'`
6. Run broader checks if focused tests expose shared fallout.
7. Run thermo-nuclear code-quality review against the diff.
8. Fix review findings.
9. Commit and push only after review and tests pass.

## Proof Plan

Primary simulator proof:

```bash
rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'
```

Required proof facts:

- composer clears within the configured UI budget
- pending outbound row appears within the configured UI budget
- canonical row replaces pending row
- composer automation value contains `message-focused=false` after send
- if the software keyboard is visible during the test, it is gone after send

Focused Swift proof:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

This protects the data-side send behavior while the UI focus layer changes.

## Implementation Result

Implemented on 2026-06-04. Both focused proof commands passed:

- `rtk swift test --filter ThreadDetailStoreTests`: 64 tests, 0 failures.
- `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'`: pass.

The passing simulator artifact is
`/tmp/codex-client/sim-ui-user-message-20260604T145112Z/user-message-latency.json`.
That run measured composer focus clear, keyboard dismissal, local composer
clear, and pending outbound row at 589 ms, all under the configured 700 ms UI
budget.

## Side Doors And Explicit Non-Fixes

- Do not put keyboard dismissal in `ThreadDetailStore`; it is not UI state.
- Do not send a fake tap into the transcript to dismiss the keyboard.
- Do not add a root `onTapGesture` that competes with row/request controls.
- Do not depend only on `scrollDismissesKeyboard`; send must explicitly clear
  focus because the user should not need to scroll after sending.
- Do not introduce app-wide focus state. This bug is local to thread-detail
  input fields.
