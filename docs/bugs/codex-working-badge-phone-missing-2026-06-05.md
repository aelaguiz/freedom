---
title: Codex working badge missing on physical phone
date: 2026-06-05
status: blocked
owners:
  - Codex Dock
reviewers: []
related:
  - docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05.md
  - docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05_WORKLOG.md
---

<!-- bugs:block:tldr -->
## TL;DR

- Symptom: The physical iPhone shows Codex sessions but does not show the
  `Codex is working` row badge.
- Impact: The phone UI cannot be trusted as live-session truth.
- Most likely cause: phone-specific runtime state, not relay data and not the
  current Swift badge renderer. The live relays are returning
  `status: "running"` rows, the iPhone saved host list is correct, and the
  current simulator app renders those rows with visible badges.
- Phone-specific blockers: the physical iPhone is on older installed build
  `20260605003015`; `devicectl` launch and diagnostics copy hang; unified log
  collection is blocked by `log: Must be root to collect logs from attached
  device`.
- Next action: get a fresh physical app launch/install proof, then verify the
  phone UI against the same relay rows.
- Status: blocked on physical-phone launch/log/diagnostic access from this
  session.

<!-- bugs:block:analysis -->
## Bug North Star

The app should show `Codex is working` on every visible Dock row whose relay
card payload has `status: "running"`.

## Bug Summary

The current relay path is producing running rows. The current simulator build is
rendering those rows with visible `Codex is working` badges. The physical phone
has the correct saved relay host list but remains the only observed failing
surface. This session cannot force a physical relaunch, copy physical
diagnostics, or collect physical app logs.

## Evidence

- Current `dock/subscribe` against `ws://amir-m5.fairy-salmon.ts.net:4510`
  returned `282` rows with `11` `running` and `271` `dormant`.
- Current `dock/subscribe` against `ws://home.fairy-salmon.ts.net:4510`
  returned the first `250` rows with `4` `running` and `246` `dormant`.
- The simulator was relaunched with
  `SIM_LAUNCH_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- The simulator installed build was `20260605031906`.
- Simulator UI dump artifact:
  `/tmp/codex-client/live-badge-ui-dump-20260605T031918Z/sim-ui-dump.json`.
- Simulator screenshot:
  `/tmp/codex-client/live-badge-sim-screenshot-20260605T032019Z.png`.
- The simulator UI dump contained visible rows with `status=running` and visible
  `Codex is working` labels.
- Current simulator screenshot:
  `/tmp/codex-client/live-badge-current-sim-20260605T033902Z.png`.
- The current simulator screenshot shows `Online 2/2` and multiple visible
  real relay rows with `Codex is working` badges.
- The physical iPhone app metadata reports:
  `Codex Dock com.aelaguiz.CodexDockApp 0.1.0 20260605003015`.
- Physical config readback now verifies hosts:
  `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- Physical launch command hung and was stopped:
  `rtk make device-launch DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`.
- Physical diagnostics copy hung and was stopped:
  `rtk make device-debug-bundle DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVICE_DEBUG_BUNDLE_DIR=/tmp/codex-client/device-debug-badge-20260605T034000Z`.
- Physical log collection failed with:
  `log: Must be root to collect logs from attached device`.

## Investigation

Ranked hypotheses:

1. Physical iPhone is not running the same installed app/config state as the
   simulator proof. Evidence: physical build `20260605003015` differs from
   simulator build `20260605031906`; later phone launch/debug reads hang.
2. Physical iPhone has stale in-app stream/render state. Evidence: the saved
   host list is correct, relays are current, and a fresh simulator launch shows
   the badges immediately.
3. Relay data is wrong. Evidence argues against this: both live relay endpoints
   return `status: "running"` rows, and the current simulator renders the badge.
4. Swift row rendering is wrong. Evidence argues against this for current code:
   `DockRowStatusKind.running.visibleBadgeLabel` returns `Codex is working`, and
   the simulator screenshot shows the badge.

Verdict: blocked for phone-specific proof, but the root cause is no longer the
relay payload, saved phone host config, or current Swift rendering path.

<!-- bugs:block:fix_plan -->
## Fix Plan

No code fix is selected yet.

Minimal verification/remediation plan:

1. Install/configure/relaunch the current build on
   `CB9FFF0E-89AD-57B5-9C00-6552D814875E`.
2. Verify the installed build number matches the new `APP_BUILD_NUMBER`.
3. Verify the saved host list is
   `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
4. Re-check the phone UI for visible `Codex is working` rows.

<!-- bugs:block:implementation -->
## Implementation

No code changed for this bug analysis.

## Verification Plan

- Relay truth: direct `dock/subscribe` status counts from both relay hosts.
- Current app truth: simulator UI dump plus screenshot.
- Physical phone truth: blocked until config/log access works or a fresh install
  can be verified.
