# Phase 6 Thermonuclear Code Quality Review

Date: 2026-05-28

Scope: Phase 6 multi-host Dock scan expansion, host registry, local metadata,
filters/grouping, launch env, and duplicate-simulator guardrail.

Verdict: pass with two maintainability watch items.

## Blocking Findings

None.

## Non-Blocking Findings

1. `DockStore` is the right owner, but it should not become the generic
   Archive/Hosts view model.
   - Severity: non-blocking.
   - Why it matters: Phase 7 will add Archive and Hosts surfaces, and the easy
     mistake is to bolt every screen-specific branch into `DockStore`.
   - Why it is acceptable now: Phase 6 needed one canonical normalized state
     owner, and `DockStore` is still under 1,000 lines with focused tests.
   - Required follow-up: if Phase 7 adds substantial projection logic, extract
     projection/helpers rather than adding surface-specific conditionals.

2. `make app` launch env is dense.
   - Severity: non-blocking.
   - Why it matters: a very long shell recipe is harder to maintain.
   - Why it is acceptable now: it centralizes the only supported launch path,
     prints the endpoint and host list, keeps legacy env alive, and prevents
     duplicate-simulator confusion.
   - Required follow-up: extract launch env assembly if another phase adds more
     variables.

## Code-Quality Assessment

- `HostRegistry` is small and direct. It preserves legacy one-host env fallback
  while supporting scoped multi-host env without introducing a separate config
  service.
- `DockStore` uses task-group fan-out and returns per-host load states. One
  host failure is represented in state instead of turning into a global error.
- Host-scoped identity stays intact through `DockRowViewModel`, detail
  navigation, and local metadata keys.
- `LocalThreadMetadataStore` is app-local and file-backed. It does not mutate
  backend thread names or introduce sync semantics before they are designed.
- `DockView` remains a rendering/projection surface. It does not call raw
  protocol APIs or load hosts itself.
- The new filter empty states are small and user-facing; they do not alter
  classification.
- `scripts/sim.py terminate-others` is a narrow guardrail for the exact
  duplicate-simulator failure mode observed during real testing.
- No mocks, fake rows, or guessed statuses were added.

## Architecture Review

The implementation keeps ownership clean:

- `HostRegistry` owns environment-to-host parsing.
- `DockStore` owns normalized multi-host state and row projection.
- `LocalThreadMetadataStore` owns app-local persisted labels/colors.
- `DockView` renders state and sends user metadata actions back to the store.
- `ThreadDetailStore` still receives the correct host from host-scoped row
  identity.
- `Makefile` remains the canonical developer launch path.

The main code-judo move was to widen `DockStore` instead of introducing a new
parallel `MultiHostSessionStore`. That avoids duplicate state ownership before
Archive and Hosts exist.

## Drift And Side-Door Review

- The app entry point now uses `HostRegistry.fromEnvironment()`, so multi-host
  config is not test-only.
- The single-host initializer remains only as a compatibility adapter.
- `make app` writes and launches with the new host-registry env while keeping
  legacy env for existing tests/tools.
- Full endpoint display closes the `:4500` vs `:4510` drift blind spot.
- The duplicate booted simulator app path is addressed by terminating Codex
  Dock on non-target booted simulators before launch.

## Verification Context

Verification reported in the worklog:

- `rtk swift test` passed 63 tests with 4 optional live-host tests skipped.
- `rtk node --check scripts/dock-relay.mjs` passed.
- `rtk npm run test:relay` passed 3 tests.
- Multi-host simulator launch passed with `Amir-M5` live and `Home`
  intentionally offline.
- Default simulator launch passed on canonical `iPhone 17`.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
  -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- `rtk git diff --check` passed.
- Screenshots:
  - `/tmp/codex-dock-phase6-multi-host-offline.png`
  - `/tmp/codex-dock-phase6-default-live.png`

## Final Judgment

Phase 6 is structurally acceptable. It expands breadth from the working
single-host control path, keeps real server state authoritative, preserves the
detail/control path, proves offline-host isolation in the simulator, and avoids
mocking status. Commit it, then make Phase 7 reuse the same registry/state path
instead of adding separate Archive or Hosts stores.
