# Codex Dock Thread Detail Message Flow Goals

Date: 2026-05-29

This document records the desired user-visible behavior for the Codex Dock
thread detail message area.

## Goal Behavior

- The thread detail view should show messages newest first.
- The thread detail message area should have one message-type filter control.
- The filter control should filter the visible list by message type.
- Clearing the filter should return the list to all messages, still newest
  first.
- The message area should not add extra timeline modes, alternate ordering
  modes, or secondary behaviors beyond newest-first display and message-type
  filtering.
- Every visible message card should be rendered by one shared message control.
- The shared message control may display different message types, labels,
  icons, status badges, and bodies, but it should remain one control.
- The thread detail message area should not contain competing card controls
  that render similar message content in different ways.
- Any complex card/type split that is not needed for the single newest-first
  filtered message list should be removed from the user-visible thread detail
  message area.
- The default state should be simple: all messages, newest first, no filter.
- Filtered states should be simple: selected message type only, newest first.
- The clear-filter action should be obvious and should only clear the selected
  message-type filter.

## Non-Goals

- This document does not define an implementation plan.
- This document does not diagnose current behavior.
- This document does not assign phases, owners, tests, or code changes.
