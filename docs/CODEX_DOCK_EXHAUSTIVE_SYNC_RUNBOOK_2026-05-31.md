# Codex Dock Exhaustive Sync Runbook

Date: 2026-05-31
Plan: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`
Implementation log:
`docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md`

## Purpose

Use this runbook to prove the Dock relay and client stay in sync with local
Codex state over time. A pass means the client-used relay routes and the
literal simulator display receive the data they need, stay current, and do not
exceed the configured lag budget.

Eventual correctness is not enough. If a row, detail item, request card, stale
state, or resolution appears only after the lag budget, the run fails.

## Prerequisites

Start or reuse the local service stack:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
```

The normal local relay path is `ws://127.0.0.1:4510` for simulator proof and
`ws://<Mac host>:4510` for physical phone proof. Do not point the app at the raw
authenticated app-server on `:4500` for completion evidence.

Use `/tmp/codex-client/...` for reports. Do not put raw real-home reports in the
repo unless they have been intentionally sanitized and reviewed.

## Fast Local Checks

Run these after relay harness code changes:

```bash
rtk node --check scripts/dock-relay-sync-audit.mjs
rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs
rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs
rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs
rtk npm run test:relay
```

Run these after Swift client route, Dock store, or detail-store changes:

```bash
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

If `ThreadDetailStoreTests` times out in an unrelated voice-capture test, record
the exact failing test and rerun the exact test. Do not claim broad
`ThreadDetailStoreTests` proof until the broad run is clean.

## Relay Client-Path Proof

One-shot real local proof:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode soak \
  --duration-ms 0 \
  --sample-interval-ms 1 \
  --settle-ms 1000 \
  --dock-collection-timeout-ms 120000 \
  --stream-compare-attempts 5 \
  --stream-compare-delay-ms 1000 \
  --exhaustive \
  --detail sampled \
  --detail-limit 1 \
  --detail-observe-ms 100 \
  --json-out /tmp/codex-client/sync-audit-real-home-exhaustive.json \
  --summary-out /tmp/codex-client/sync-audit-real-home-exhaustive.md \
  --summary-only \
  --fail-on-diff
```

Over-time client-route soak with forced `dock/resync`:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode soak \
  --client-path-only \
  --force-dock-resync \
  --duration-ms 65000 \
  --sample-interval-ms 30000 \
  --settle-ms 1000 \
  --dock-collection-timeout-ms 120000 \
  --stream-compare-attempts 5 \
  --stream-compare-delay-ms 1000 \
  --max-stream-lag-ms 2000 \
  --detail sampled \
  --detail-limit 5 \
  --detail-observe-ms 100 \
  --json-out /tmp/codex-client/sync-audit-real-home-client-path-force-resync.json \
  --summary-out /tmp/codex-client/sync-audit-real-home-client-path-force-resync.md \
  --summary-only \
  --fail-on-diff
```

Required scenario matrix at relay level:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --mode scenario \
  --scenario all \
  --scenario-repetitions 2 \
  --client-path-only \
  --detail none \
  --dock-collection-timeout-ms 120000 \
  --max-stream-lag-ms 2000 \
  --json-out /tmp/codex-client/scenario-all-client-path.json \
  --summary-out /tmp/codex-client/scenario-all-client-path.md \
  --summary-only \
  --fail-on-diff
```

The relay proof must include `initialize`, `initialized`, `dock/subscribe`,
`dock/update`, `dock/resync`, `thread/read`, `thread/turns/list`, and
`thread/resume` where those routes are in scope. Oracle-only routes can explain
drift, but they do not prove client delivery.

## Simulator Display Proof

The completion-grade simulator proof uses the real `iPhone 17` app path. It
must start the simulator sampler first, mutate the same relay the app is using,
and compare literal displayed UI samples against the relay/client-route report.

Run the full controlled simulator matrix twice:

```bash
rtk make sim-ui-controlled-matrix-proof \
  SIM='iPhone 17' \
  SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-$(date -u +%Y%m%dT%H%M%SZ) \
  SIM_UI_CONTROLLED_MATRIX_PASSES=2 \
  MAX_UI_LAG_MS=2000 \
  SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

The default matrix scenarios are:

- `detail-history-request`
- `large-list-checkpoint`
- `thread-activity`
- `server-request`
- `source-refresh`
- `live-lease-expiry`
- `multi-host-isolation`
- `spawn-edge`
- `resync-gap`
- `rapid-mutations`

The matrix writes one scenario directory per pass under
`SIM_UI_CONTROLLED_MATRIX_ROOT`, plus:

```text
<root>/controlled-simulator-matrix.json
<root>/controlled-simulator-matrix.md
```

Each scenario directory contains:

```text
relay-client-path.json
relay-client-path.md
ui-samples.jsonl
simulator-ui-sync.json
simulator-ui-sync.md
controlled-fixture.out.log
```

For focused debugging, run one scenario:

```bash
rtk make sim-ui-controlled-scenario-sync-proof \
  SIM='iPhone 17' \
  SIM_UI_SYNC_SCENARIO=detail-history-request \
  SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-debug \
  SIM_UI_SYNC_DURATION_MS=20000 \
  SIM_UI_SYNC_SAMPLE_MS=250 \
  SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 \
  MAX_UI_LAG_MS=2000 \
  SIM_UI_SYNC_CHECKPOINT_SWEEP=1 \
  SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

Use `detail-history-request` when checking opened-thread detail history,
request-card visibility, real request action taps, resolved request state, and
detail sweep completeness. Use `resync-gap` when checking stream sequence-gap
recovery through `dock/resync`.

## Matrix Verification Only

If scenario reports already exist, verify them without rerunning the simulator:

```bash
rtk make sim-ui-controlled-matrix-verify \
  SIM_UI_MATRIX_REPORT_DIRS='/tmp/codex-client/run/pass-1/detail-history-request /tmp/codex-client/run/pass-1/large-list-checkpoint' \
  SIM_UI_MATRIX_MIN_PASSES=1 \
  MAX_UI_LAG_MS=2000 \
  SIM_UI_MATRIX_JSON=/tmp/codex-client/sim-ui-controlled-matrix.json \
  SIM_UI_MATRIX_MD=/tmp/codex-client/sim-ui-controlled-matrix.md
```

For a completion gate, use `SIM_UI_MATRIX_MIN_PASSES=2` and distinct report
directories for each pass. Reusing the same artifact twice is not valid proof.

## Physical Phone Proof

Physical-phone proof is still required before the whole goal can be called
complete. It is not replaced by simulator or local relay proof.

Install and configure Amir's iPhone 17 Pro:

```bash
rtk make iphone-17-pro
```

Install and configure the iPhone 14:

```bash
rtk make iphone-14
```

Verify saved host configs without reinstalling:

```bash
rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
```

Physical completion evidence must show the installed app connects to the
relay-backed host path, renders real `DockThreadCard` rows, and shows
offline/error UI when that same host path is unavailable.

If physical Mobile MCP reports `WebDriverAgent is not running on device`, stop
retrying physical Mobile MCP for that task and record that exact blocker. Use
simulator/local proof only for the parts it actually proves.

## Reading Results

Treat a run as `pass` only when all of these are true:

- the command exits 0;
- the JSON report has `ok: true`;
- `clientPathOK` is true when client-path proof is in scope;
- matrix reports show every required scenario passed;
- no `streamLagFailures`, `scenarioTransitionFailures`, or
  `detailTransitionFailures` are present;
- max relay/UI lag is at or below `MAX_UI_LAG_MS`;
- checkpoint sweeps and detail sweeps meet the required row counts;
- unsupported facts are classified, not hidden.

Treat a run as `fail` when the report has missing rows, duplicates, stale data
shown as fresh, wrong host/thread/detail identity, skipped transitions, failed
request-card visibility/resolution, or lag over budget.

Treat a run as `blocked` only when the command could not exercise the intended
path because Xcode, a simulator, a physical device, signing, services, or
environment variables were unavailable. Record the exact command and exact
blocker.

Treat a finding as `outside-contract` only when the report explicitly classifies
the fact as outside current app-server or client contract. A client-required
`product_gap` blocks completion.

## CI-Safe Subsets

Use these in ordinary local or CI-like checks where no simulator or phone is
available:

```bash
rtk node --check scripts/dock-relay-sync-audit.mjs
rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs
rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs
rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs
rtk npm run test:relay
```

Use this to validate Makefile wiring without launching a simulator:

```bash
rtk make -n sim-ui-controlled-matrix-proof \
  SIM='iPhone 17' \
  SIM_UI_CONTROLLED_MATRIX_PASSES=2 \
  MAX_UI_LAG_MS=2000
```

These CI-safe subsets do not replace the actual `iPhone 17` simulator matrix or
physical-phone proof.

## Redaction Rules

Do not log or publish:

- `OPENAI_API_KEY`;
- raw app-server bearer tokens;
- base64 audio or raw audio bytes;
- prompt text;
- transcript text;
- full JSON-RPC payloads.

The harness reports use route counts, ids, statuses, timings, redaction-safe
fingerprints, and invariant ids. If a new report includes sensitive data, treat
that as a harness failure before sharing the artifact.
