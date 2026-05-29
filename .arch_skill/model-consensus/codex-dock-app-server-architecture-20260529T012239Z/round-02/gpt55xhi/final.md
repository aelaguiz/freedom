## Signoff

converged-with-required-edit

## Required Edits Before Canonical Doc

Add the explicit per-device endpoint-profile invariant. The parent candidate has the right logical-host model, but the canonical doc still needs the exact iPhone 17 Pro vs iPhone 14 endpoint separation.

## Reason

- I sign off on the main architecture: relay as Mac-side Host Agent, raw `ws://127.0.0.1:4500` as history anchor, and no phone direct-to-raw path.
- I accept Claude/Opus’s refinement: dashboard membership, order, and cursor should be history-plane truth; live data should repaint status only.
- The `HistoryClient` / `LiveStatusCache` / `SessionRouter` split is cleaner than a generic relay merger and directly prevents the socket storm.
- Point 8 is correctly cautious: union `sourceKinds` is elegant, but dual scopes are acceptable if they stay pooled and do not multiply hosts/sockets.
- The only missing required architecture detail is device config isolation with the exact endpoint sets from `Makefile`/`AGENTS.md`.

## Exact Wording To Include

“Dashboard `thread/list` membership, order, and cursor are history-plane truth from the Dock-owned history app-server at `ws://127.0.0.1:4500`. Live status may repaint `status`, `attention`, `ownerEndpoint`, and degradation metadata, but live status must never move, filter, insert, or page dashboard rows.”

“Exactly one logical host exists per relay instance id. Endpoint aliases are ordered failover transports for that host, never separate hosts and never separate load sources.”

“iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E` uses the Tailscale endpoint profile: `amir-m5.fairy-salmon.ts.net:4510`, `home.fairy-salmon.ts.net:4510`. iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` uses the local endpoint profile: `Amir-M5.local:4510`, `192.168.50.74:4510`. These profiles are separate saved device configs and must not leak into each other.”

“A timed-out upstream JSON-RPC socket is untrusted: it must be quarantined and closed or terminated within a bounded deadline.”

“`ps` discovery is transitional only. It may feed `LiveStatusCache`, but it must be cached, bounded, visible in `/statusz`, and absent from dashboard request hot paths.”