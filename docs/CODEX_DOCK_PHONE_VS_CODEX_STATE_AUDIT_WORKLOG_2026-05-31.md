# Codex Dock Phone vs Codex State Audit Worklog - 2026-05-31

## Goal

Keep one working log for comparing what the iPhone 17 simulator actually shows
against the current Codex-backed Dock truth served by the relays.

This work log is evidence-first. Do not treat green process health as proof that
the phone display is correct. The useful comparison is:

1. What the phone/simulator renders.
2. What `dock/subscribe` says the current relay-backed Dock card truth is.
3. Which client filters or state rules explain any difference.

## 2026-05-31T22:02-22:05Z - First phone-vs-Codex audit after relay cache reset

### Commands and Artifacts

- Attempted the repo-owned rendered UI proof:

```sh
rtk make sim-ui-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR='/tmp/codex-client/phone-vs-codex-audit-20260531T170000-local' SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=1000 SIM_UI_SYNC_RELAY_DURATION_MS=45000 SIM_UI_SYNC_RELAY_SAMPLE_MS=5000 MAX_UI_LAG_MS=3000
```

- That proof failed before it produced comparison artifacts.
  - Failing test: `CodexDockDisplayedSyncProofTests.testSamplesRelayBackedDockDisplayOverTime()`
  - Test log: `.codex-dock/logs/sim-ui-sync-test-20260531220221.log`
  - Partial proof directory: `/tmp/codex-client/phone-vs-codex-audit-20260531T170000-local/`
  - Only partial file present: `relay-client-path.out.log`, zero bytes.

- Restored the normal iPhone 17 simulator app launch:

```sh
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
```

- Captured direct relay truth from both configured hosts:
  - JSON: `/tmp/codex-client/phone-vs-codex-audit-20260531T170000-direct/relay-merged-dock-truth.json`

- Captured visible iPhone 17 simulator screen:
  - Screenshot: `/tmp/codex-client/phone-vs-codex-audit-20260531T170000-direct/iphone17-visible-dock.png`

### Service State

- Mac service bundle status: `ready`.
- Home service bundle status: `ready`.
- Both relay processes answered `dock/subscribe`.

### Relay Truth

At `2026-05-31T22:03:50.974Z`, the merged relay truth said the global newest rows were:

| Rank | Host | Thread | Title | Activity | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Amir-M5 | `019e7e7d-66ca-7280-9aa0-2e272f1752b1` | `Audit card pinning logic` | `2026-05-31T22:03:36.000Z` | `idle` |
| 2 | Amir-M5 | `019e8004-daac-7900-a401-b2ecdaf47907` | `Ramp up on up on our [SCENE_RENDERING...]` | `2026-05-31T22:03:23.000Z` | `idle` |
| 3 | Home | `019e79b7-2eb3-7302-91aa-4cd50f2d8094` | `We were doing work on a hill climb experiment...` | `2026-05-31T22:02:50.000Z` | `dormant` |
| 4 | Amir-M5 | `019e8005-b88a-7820-8e27-2ac8287de99f` | `start a doc pack for 3d card effects...` | `2026-05-31T22:02:23.000Z` | `idle` |
| 5 | Amir-M5 | `019e7f69-2d82-7570-b6d4-5d48b46e75f4` | `Ramp up on our mini stage epic work...` | `2026-05-31T21:50:00.000Z` | `idle` |
| 6 | Amir-M5 | `019e7f87-7699-72d2-a864-a7025138fcfb` | `Find open audit items` | `2026-05-31T21:49:06.000Z` | `idle` |
| 7 | Amir-M5 | `019e7ffe-aaf3-7853-a476-66a5896dd6b5` | `Find open audit items` | `2026-05-31T21:46:17.000Z` | `dormant` |

Mac relay freshness:

- `complete=false`
- `totalRows=197`
- `freshness.status=stale`
- `lastError=human-started thread validation failed`

Home relay freshness:

- `complete=false`
- `totalRows=961`
- `freshness.status=fresh`
- `lastError=null`
- No stale `000000000000:*` order keys were observed after the relay cache reset.

### Phone/Simulator Display

At `2026-05-31T22:04Z`, after the normal iPhone 17 simulator launch, the visible Dock screen reported:

- Root state: `loaded; rows=1158; pinned=0; lens=newest; search=false; filters=0`
- Summary: `1,153 shown ... Idle hidden ... Partial`
- Connectivity badge: `Online 2/2`
- Connectivity value: `Partial: Amir-M5: Partial window`

The first visible rows were:

| Visible Order | Host | Thread | Title | Displayed Age |
| --- | --- | --- | --- | --- |
| 1 | Home | `019e79b7-2eb3-7302-91aa-4cd50f2d8094` | `We were doing work on a hill climb experiment...` | `1m ago` |
| 2 | Amir-M5 | `019e7ffe-aaf3-7853-a476-66a5896dd6b5` | `Find open audit items` | `18m ago` |
| 3 | Amir-M5 | `019e7faf-50a7-7582-82bf-34c92e4f20a0` | `Ramp up on our animation engine...` | `56m ago` |
| 4 | Amir-M5 | `019e7fc6-e39d-7740-9d55-a44082d97cae` | `ramp up on the work in the group files...` | `58m ago` |

### Current Finding

The current work is not missing from Codex or the relay. The current Amir-M5
thread `019e7e7d-66ca-7280-9aa0-2e272f1752b1` is rank 1 in relay truth with
activity at `2026-05-31T22:03:36.000Z`.

The reason it is not visible at the top of the phone screen is the app's
default `Idle hidden` filter.

The newest relay rows are present but have status `idle`, and Dock is currently
hiding idle rows by default. The phone summary proves this: it says `rows=1158`
but only `1,153 shown`, so five rows are hidden. The top hidden rows include the
fresh current Amir-M5 work.

After applying the client's `Idle hidden` rule, the visible phone order matches
the filtered relay order:

1. Home hill-climb row, status `dormant`.
2. Amir-M5 `Find open audit items`, status `dormant`.
3. Amir-M5 animation-engine ramp-up, status `dormant`.
4. Amir-M5 group-files ramp-up, status `dormant`.

### Working Interpretation

This is no longer the stale SQLite `orderKey` bug. That was fixed by deleting
and rebuilding the relay caches.

The remaining user-visible problem is filter/status semantics:

- The relay/card truth knows the newest current sessions.
- Those newest sessions can be marked `idle`.
- The Dock screen defaults to `Idle hidden`.
- Therefore current work can be correctly present in Codex and still be hidden
from the default phone view.

### Open Items

- Decide whether `Idle hidden` should be the default for `Newest`.
- Decide whether a recently active human session should ever be hidden just
  because its current runtime status is `idle`.
- Fix the repo-owned `sim-ui-sync-proof` path so it produces usable comparison
  artifacts when the displayed UI proof fails.
