# Codex Dock iOS Mobile MCP Diagnosis

Device: `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` (`feat_anim_1 - iPhone 17`, iOS 26.5 simulator)
Started: Thursday May 28 17:46:20 UTC 2026
Scope: Diagnose Mobile MCP control for Codex Dock, with physical iPhone blocker recorded and simulator proof captured.
Status: Partial

Physical device checked: `00008110-000E04940240A01E` (`iPhone`, iOS 26.2 real device).

Physical blocker: `WebDriverAgent is not running on device (tunnel okay, port forwarding okay), please see https://github.com/mobile-next/mobile-mcp/wiki/`

| # | File | Screen | Notes |
|---:|---|---|---|
| 001 | 001_simulator_archive_after-tab-tap.png | Archive tab after Mobile MCP tap | Mobile MCP launched `com.aelaguiz.CodexDockApp` on the iOS 26.5 simulator, tapped Archive at `(201, 822)`, and the app changed screens. |
| 002 | 002_simulator_dock_after-return-tap.png | Dock tab after return tap | Mobile MCP tapped Dock at `(115, 822)` and returned to the live Dock list with relay data visible. |
