# Phase 7 Thermonuclear Code Quality Review

Date: 2026-05-28

Scope: Phase 7 archive/unarchive protocol, relay support, Archive screen,
Hosts screen, shared host registry propagation, tests, and docs.

Verdict: pass with two non-blocking polish items.

## Blocking Findings

None.

## Non-Blocking Findings

1. Host edits are runtime-only.
   - Severity: non-blocking.
   - Why it matters: a user-added host disappears after app relaunch.
   - Why it is acceptable now: Phase 7 required a utilitarian add/edit/test
     flow using existing registry state. Persistence was not a stated gate, and
     Makefile/env remains the canonical launch configuration.
   - Required follow-up: decide in Phase 8 or post-MVP whether host settings
     should persist in app storage.

2. Shared UI components should eventually move out of `DockView.swift`.
   - Severity: non-blocking.
   - Why it matters: Archive and Hosts now use common Dock views from a Dock
     feature file.
   - Why it is acceptable now: this is not duplicated behavior, and the more
     important projection logic moved into `SessionRowProjector`.
   - Required follow-up: move common SwiftUI components into a common feature
     file if Phase 8 changes them.

## Code-Quality Assessment

- `AppServerMethods`, DTOs, and `AppServerClient` match the local Codex
  protocol: `thread/archive` returns an empty response and `thread/unarchive`
  returns a restored thread.
- `AppServerDockClient` now uses one client helper for list/archive/unarchive
  and maps transport/server failures through the existing failure model.
- `DockSessionLoading` takes an `archived` flag, which keeps Archive on the
  same loading abstraction instead of creating a second protocol family.
- `DockSessionArchiving` is narrow and explicit.
- `DockStore.archive` does not remove a row optimistically. It calls the real
  server, refreshes, and preserves visible state on failure.
- `ArchiveStore` loads archived rows from `thread/list archived: true` and
  restores through `thread/unarchive`.
- `HostSettingsStore` owns one mutable registry and exposes rows/status for the
  Hosts tab. `CodexDockRootView` propagates registry changes back into
  Dock/Archive.
- `SessionRowProjector` is the right extraction from Phase 6. It keeps Dock and
  Archive section/row status context aligned.
- The relay correctly avoids merging live loopback rows into archived
  `thread/list` calls.
- The relay forwards archive/unarchive through real app-server endpoints; no
  fake archive state was introduced.
- Tests cover typed archive/unarchive, archive success/failure, Archive restore,
  host add/edit/test, relay archived-list behavior, and the real relay
  archive/unarchive round trip.

## Architecture Review

The implementation keeps the server authoritative:

- Archive state lives in Codex app-server, not local hidden-row state.
- The iPhone app talks to the phone-reachable relay at
  `ws://192.168.50.117:4510`.
- The relay uses the raw history app-server for archived lists and unarchive.
- Dock and Archive share host/thread identity and row projection.
- Hosts changes are registry changes, not a parallel host-status side table.
- V1 intentionally excludes AIMGR, Rotate behavior, and account switching.

The main structural improvement is extracting `SessionRowProjector`. That
directly addresses the Phase 6 audit concern that `DockStore` should not become
the generic Archive/Hosts projection sink.

## Drift And Side-Door Review

- `CodexDockApp` constructs `CodexDockRootView(registry:)`, so Archive and Hosts
  are app runtime surfaces, not preview-only code.
- The one-host root initializer remains only for preview/test compatibility.
- Relay method names match app-server protocol names.
- Archived `thread/list` no longer mixes live rows, which would make Archive
  disagree with Dock.
- V1 exclusion check over implementation code found no AIMGR, Rotate, AI
  Manager, or account-switching integration.

## Verification Context

Verification reported in the worklog:

- `rtk swift test` passed 69 tests with 5 optional live-host tests skipped.
- `rtk node --check scripts/dock-relay.mjs` passed.
- `rtk npm run test:relay` passed 5 tests.
- `rtk make dock-relay-restart` restarted the phone-reachable relay with the
  new code.
- Explicit real archive/unarchive round trip passed through
  `ws://192.168.50.117:4510`.
- `rtk make app SIM='iPhone 17'` built, installed, and launched the app on
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
  -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- `rtk git diff --check` passed.
- Screenshots:
  - `/tmp/codex-dock-phase7-dock.png`
  - `/tmp/codex-dock-phase7-archive.png`
  - `/tmp/codex-dock-phase7-hosts.png`
  - `/tmp/codex-dock-phase7-hosts-tested.png`

## Final Judgment

Phase 7 is structurally acceptable. It uses the supported Codex app-server
archive/unarchive methods, proves a reversible real-host round trip through the
phone-reachable relay, adds the Archive and Hosts MVP surfaces, keeps host
state shared, and avoids AIMGR/Rotate/account-switching scope creep. Commit it.
