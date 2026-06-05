APP_SERVER_DIR ?= .codex-dock
CODEX_HOME ?=
APP_SERVER_HOST ?= $(shell tailscale status --json 2>/dev/null | python3 -c 'import json, sys; dns = json.load(sys.stdin).get("Self", {}).get("DNSName", "").rstrip("."); print(dns) if dns else sys.exit(1)' 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || hostname)
NODE_BIN ?= /opt/homebrew/bin/node
APP_SERVER_ABS_DIR := $(abspath $(APP_SERVER_DIR))
DOCK_RELAY_PORT ?= 4510
DOCK_RELAY_LISTEN_HOST ?= 0.0.0.0
DOCK_RELAY_WS ?= ws://$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)
DOCK_RELAY_PROBE_WS ?= $(DOCK_RELAY_WS)
DOCK_RELAY_LEAK_CHECK_ITERATIONS ?= 25
DOCK_RELAY_LABEL ?= com.aelaguiz.codex-dock.relay
DOCK_RELAY_PID := $(APP_SERVER_ABS_DIR)/dock-relay.pid
DOCK_RELAY_LOG := $(APP_SERVER_ABS_DIR)/logs/dock-relay.log
DOCK_RELAY_ERR_LOG := $(APP_SERVER_ABS_DIR)/logs/dock-relay.err.log
DOCK_RELAY_PLIST := $(APP_SERVER_ABS_DIR)/services/$(DOCK_RELAY_LABEL).plist
ENV_FILE ?= $(APP_SERVER_DIR)/service.env
HOST_ENV_FILE ?= $(APP_SERVER_DIR)/host.env
USER_ENV_FILE ?= .env
ENV_FILE_ABS := $(abspath $(ENV_FILE))
HOST_ENV_FILE_ABS := $(abspath $(HOST_ENV_FILE))
HOST_SERVICE_SCRIPT ?= scripts/codex-dock-host-service.mjs
HOST_SERVICE_PLATFORM ?= macos
HOST_SERVICE_NETWORK_PROFILE ?= lan
HOST_SERVICE_WAIT_ATTEMPTS ?= 10
HOST_SERVICE_STATUS_FILE := $(APP_SERVER_ABS_DIR)/host-service.status.json
SIM ?= iPhone 17
SIM_PERFORMANCE_PROFILING ?= 0
SIM_LAUNCH_HOSTS ?=
APP_SCHEME ?= CodexDockApp
APP_BUNDLE_ID ?= com.aelaguiz.CodexDockApp
APP_DERIVED_DATA ?= $(APP_SERVER_ABS_DIR)/DerivedData
APP_PATH := $(APP_DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_SCHEME).app
APP_BUILD_NUMBER ?= $(shell date -u +%Y%m%d%H%M%S)
APP_FRESH_BUILD ?= 1
FORCE_LAUNCH ?= 0
DEVICE ?=
DEVICE_NAME ?= iPhone 14
DEVELOPMENT_TEAM ?= R6B8KXF3QW
DEVICE_APP_PATH := $(APP_DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_SCHEME).app
DEVICE_RELAY_HOSTS ?=
DEVICE_RELAY_HOST ?=
DEVICE_RELAY_PORT ?= $(DOCK_RELAY_PORT)
DEVICE_CONFIG_PATH ?= Library/Application Support/CodexDock/relay-config.json
IPHONE_17_PRO_DEVICE ?= CB9FFF0E-89AD-57B5-9C00-6552D814875E
IPHONE_17_PRO_RELAY_HOSTS ?= amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
IPHONE_14_DEVICE ?= 0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
IPHONE_14_RELAY_HOSTS ?= Amir-M5.local:4510,192.168.50.74:4510
SIM_RELAY_HOSTS ?= $(IPHONE_17_PRO_RELAY_HOSTS)
CODEX_DOCK_REAL_HOST_ID ?= Amir-M5
CODEX_DOCK_REAL_HOST_NAME ?= Amir-M5
CODEX_DOCK_HOSTS ?= $(SIM_RELAY_HOSTS)
CODEX_DOCK_UI_TEST_HOSTS ?= $(CODEX_DOCK_HOSTS)
CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL ?= gpt-realtime-whisper
CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY ?= low
LOG_STYLE ?= compact
LOG_PREDICATE ?= subsystem == "com.aelaguiz.CodexDock"
LOG_LAST ?= 10m
DEVICE_LOG_OUTPUT ?= /tmp/codex-client/codex-dock-device-$(shell date -u +%Y%m%dT%H%M%SZ).logarchive
RELAY_DEBUG_BUNDLE ?= /tmp/codex-client/relay-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ).json
RELAY_HOST_COMPARE_REPORT ?= /tmp/codex-client/relay-host-compare-$(shell date -u +%Y%m%dT%H%M%SZ).json
HOSTS ?= $(CODEX_DOCK_HOSTS)
SIM_DEBUG_BUNDLE_DIR ?= /tmp/codex-client/sim-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ)
DEVICE_DEBUG_BUNDLE_DIR ?= /tmp/codex-client/device-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ)
APP_TEST_ONLY ?=
SIM_UI_SYNC_DIR ?= /tmp/codex-client/sim-ui-audit-$(shell date -u +%Y%m%dT%H%M%SZ)
SIM_UI_SYNC_HOSTS ?= 127.0.0.1:$(DOCK_RELAY_PORT)
SIM_UI_SYNC_RELAY_WS ?= ws://127.0.0.1:$(DOCK_RELAY_PORT)
# XCTest accessibility polling is the proof transport, not the product path.
# Keep the default live proof short and repeatable; use scenario/matrix targets
# for intentional long-running and checkpoint-sweep coverage.
SIM_UI_SYNC_DURATION_MS ?= 15000
SIM_UI_SYNC_SAMPLE_MS ?= 1500
SIM_UI_SYNC_RELAY_DURATION_MS ?= 45000
SIM_UI_SYNC_RELAY_SAMPLE_MS ?= 30000
SIM_UI_SYNC_RELAY_DETAIL ?= none
SIM_UI_SYNC_RELAY_DETAIL_LIMIT ?= 5
SIM_UI_SYNC_RELAY_DETAIL_OBSERVE_MS ?= 100
SIM_UI_SYNC_LENSES ?= newest
SIM_UI_SYNC_SCENARIO ?= archive-toggle
SIM_UI_SYNC_SCENARIO_HOLD_MS ?= 3500
SIM_UI_SYNC_SCENARIO_REPETITIONS ?= 1
SIM_UI_SYNC_READY_TIMEOUT_MS ?= 60000
SIM_UI_SYNC_SCENARIO_THREAD_ID ?=
SIM_UI_SYNC_CODEX_HOME ?= $(CODEX_HOME)
SIM_UI_SYNC_CHECKPOINT_SWEEP ?= 1
SIM_UI_DUMP_RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
SIM_UI_DUMP_DIR ?= /tmp/codex-client/sim-ui-dump-$(SIM_UI_DUMP_RUN_ID)
SIM_UI_DUMP_JSON ?= $(SIM_UI_DUMP_DIR)/sim-ui-dump.json
SIM_UI_DUMP_MD ?= $(SIM_UI_DUMP_DIR)/sim-ui-dump.md
ifndef SIM_UI_CLIENT_RENAME_RUN_ID
SIM_UI_CLIENT_RENAME_RUN_ID := $(shell date -u +%Y%m%dT%H%M%SZ)
endif
ifndef SIM_UI_CLIENT_RENAME_DIR
SIM_UI_CLIENT_RENAME_DIR := /tmp/codex-client/sim-ui-client-rename-$(SIM_UI_CLIENT_RENAME_RUN_ID)
endif
SIM_UI_CLIENT_RENAME_SERVER_ACK_DELAY_MS ?= 1500
SIM_UI_CLIENT_RENAME_UI_BUDGET_MS ?= 700
SIM_UI_USER_MESSAGE_RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
SIM_UI_USER_MESSAGE_DIR ?= /tmp/codex-client/sim-ui-user-message-$(SIM_UI_USER_MESSAGE_RUN_ID)
SIM_UI_USER_MESSAGE_UPSTREAM_ACK_DELAY_MS ?= 2500
SIM_UI_USER_MESSAGE_UI_BUDGET_MS ?= 700
SIM_UI_USER_MESSAGE_WAIT_TIMEOUT_MS ?= 180000
EXPECTED_SCREEN ?=
EXPECTED_THREAD_ID ?=
SIM_UI_MATRIX_REPORT_DIRS ?=
SIM_UI_MATRIX_JSON ?= /tmp/codex-client/sim-ui-controlled-matrix-$(shell date -u +%Y%m%dT%H%M%SZ).json
SIM_UI_MATRIX_MD ?= /tmp/codex-client/sim-ui-controlled-matrix-$(shell date -u +%Y%m%dT%H%M%SZ).md
SIM_UI_MATRIX_MIN_PASSES ?= 2
SIM_UI_CONTROLLED_MATRIX_RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
SIM_UI_CONTROLLED_MATRIX_ROOT ?= /tmp/codex-client/sim-ui-controlled-matrix-run-$(SIM_UI_CONTROLLED_MATRIX_RUN_ID)
SIM_UI_CONTROLLED_MATRIX_SCENARIOS ?= archive-toggle detail-reconnect detail-history-request large-list-checkpoint thread-activity server-rename-notification server-status-notification server-request source-refresh live-lease-expiry multi-host-isolation spawned-private-child-status-rollup spawn-edge resync-gap rapid-mutations detail-replay-pressure current-work-visible root-catchup-window-contract mutation-ack-projection-refresh-failure foreground-resume-all-surfaces
SIM_UI_CONTROLLED_MATRIX_PASSES ?= 2
SIM_UI_CONTROLLED_MATRIX_SAMPLE_MS ?= 250
MAX_UI_LAG_MS ?= 2000
CODEX_DOCK_SIM_UI_SYNC_OUT ?=
CODEX_DOCK_SIM_UI_SYNC_DURATION_MS ?=
CODEX_DOCK_SIM_UI_SYNC_SAMPLE_MS ?=
SIM_UI_ISOLATED_RUN_ID ?= $(shell date -u +%Y%m%d%H%M%S)
SIM_UI_ISOLATED_ROOT ?= /tmp/codex-client/sim-ui-isolated-scenario-$(SIM_UI_ISOLATED_RUN_ID)
SIM_UI_ISOLATED_HOME ?= $(SIM_UI_ISOLATED_ROOT)/codex-home
SIM_UI_ISOLATED_SERVICE_DIR ?= $(SIM_UI_ISOLATED_ROOT)/service
SIM_UI_ISOLATED_METADATA ?= $(SIM_UI_ISOLATED_ROOT)/isolated-home.json
SIM_UI_ISOLATED_SOURCE_HOME ?= $(HOME)/.codex
SIM_UI_ISOLATED_MAX_ROLLOUT_BYTES ?= 3000000
SIM_UI_ISOLATED_THREAD_COUNT ?= 1
SIM_UI_ISOLATED_RELAY_PORT ?= 4521
SIM_UI_ISOLATED_RELAY_LABEL ?= com.aelaguiz.codex-dock.relay.isolated.$(SIM_UI_ISOLATED_RUN_ID)
APP_BUILD_LOG_DIR := $(APP_SERVER_ABS_DIR)/logs
HOST_SERVICE_CODEX_HOME_ARG = $(if $(CODEX_HOME),--codex-home "$(CODEX_HOME)",)
HOST_SERVICE_ARGS = --platform "$(HOST_SERVICE_PLATFORM)" --runtime-dir "$(APP_SERVER_DIR)" $(HOST_SERVICE_CODEX_HOME_ARG) --host-id "$(CODEX_DOCK_REAL_HOST_ID)" --host-name "$(CODEX_DOCK_REAL_HOST_NAME)" --network-profile "$(HOST_SERVICE_NETWORK_PROFILE)" --public-host "$(APP_SERVER_HOST)" --relay-public-url "$(DOCK_RELAY_WS)" --relay-listen-host "$(DOCK_RELAY_LISTEN_HOST)" --relay-port "$(DOCK_RELAY_PORT)" --phone-auth "none" --service-env-file "$(ENV_FILE_ABS)" --host-env-file "$(HOST_ENV_FILE_ABS)" --node-bin "$(NODE_BIN)" --relay-label "$(DOCK_RELAY_LABEL)" --relay-script "$(CURDIR)/scripts/dock-relay.mjs"
SIM_UI_SYNC_CODEX_HOME_ARG = $(if $(SIM_UI_SYNC_CODEX_HOME),--codex-home "$(SIM_UI_SYNC_CODEX_HOME)",)
SIM_UI_SYNC_SCENARIO_THREAD_ARG = $(if $(SIM_UI_SYNC_SCENARIO_THREAD_ID),--scenario-thread-id "$(SIM_UI_SYNC_SCENARIO_THREAD_ID)",)

.DEFAULT_GOAL := help

.PHONY: help contract-generate contract-check app app-test sim-ui-dump sim-ui-client-rename-proof sim-ui-user-message-latency-proof sim-ui-sync-proof sim-ui-scenario-sync-proof sim-ui-isolated-scenario-sync-proof sim-ui-controlled-scenario-sync-proof sim-ui-controlled-matrix-verify sim-ui-controlled-matrix-proof sim-sync-audit sim-config-verify device-install device-install-iphone-17-pro device-install-iphone-14 iphone-17-pro iphone-14 device-install-all device-config device-config-verify device-config-verify-all device-launch devices services env-file node-deps host-service-install host-service-start host-service-status host-service-wait host-service-stop host-service-restart host-service-logs host-service-doctor app-server app-server-status app-server-env app-server-stop app-server-restart dock-relay dock-relay-status dock-relay-stop dock-relay-restart relay-doctor relay-debug-bundle relay-host-compare sim-debug-bundle device-debug-bundle app-server-logs dock-relay-logs sim-logs device-logs sims sim sim-list sim-boot run

help:
	@printf "%s\n" "Codex Dock commands:"
	@printf "%s\n" "  rtk make contract-generate Regenerate generated contract DTOs"
	@printf "%s\n" "  rtk make contract-check    Check DockThreadCard contract fixtures and generated DTOs"
	@printf "%s\n" "  rtk make app SIM='iPhone 17' Reuse a running simulator app; otherwise build/install/launch"
	@printf "%s\n" "  SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17' Launch simulator with perf profiling"
	@printf "%s\n" "  SIM_LAUNCH_HOSTS=host:4510 SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17' Launch simulator against a diagnostic host set"
	@printf "%s\n" "  FORCE_LAUNCH=1 rtk make app SIM=<UDID> Fresh build/install/relaunch by simulator ID"
	@printf "%s\n" "  rtk make app-test SIM='iPhone 17' Run generated-project app tests in a simulator"
	@printf "%s\n" "  rtk make sim-ui-dump SIM='iPhone 17' Dump the current simulator Dock/Thread screen as accessibility JSON"
	@printf "%s\n" "  rtk make sim-ui-client-rename-proof SIM='iPhone 17' Run controlled client rename latency proof"
	@printf "%s\n" "  rtk make sim-ui-user-message-latency-proof SIM='iPhone 17' Run controlled user-message send latency proof"
	@printf "%s\n" "  rtk make sim-ui-sync-proof SIM='iPhone 17' Run real relay-backed displayed-UI sync proof"
	@printf "%s\n" "  rtk make sim-ui-scenario-sync-proof SIM='iPhone 17' Run displayed-UI scenario transition proof"
	@printf "%s\n" "  rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' Seed temp Codex home and run isolated displayed-UI transition proof"
	@printf "%s\n" "  rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' Run controlled fixture displayed-UI scenario proof"
	@printf "%s\n" "  rtk make sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS='<dirs>' Verify controlled simulator report matrix"
	@printf "%s\n" "  rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' Run and verify the full controlled simulator matrix"
	@printf "%s\n" "  rtk make sim-config-verify SIM='iPhone 17' Verify generated simulator relay config"
	@printf "%s\n" "  rtk make device-install    Fresh build/install/configure/launch the default physical iPhone"
	@printf "%s\n" "  rtk make device-install DEVICE=<UDID> Fresh build/install/configure/launch a physical iPhone"
	@printf "%s\n" "  rtk make iphone-17-pro     Fresh build/install/configure/launch Amir's iPhone 17 Pro"
	@printf "%s\n" "  rtk make iphone-14         Fresh build/install/configure/launch Amir's iPhone 14"
	@printf "%s\n" "  rtk make device-install-all Install/configure iPhone 17 Pro and iPhone 14"
	@printf "%s\n" "  rtk make device-config DEVICE=<UDID> Write saved relay hosts for one physical iPhone"
	@printf "%s\n" "  rtk make device-config-verify DEVICE=<UDID> Read back one physical iPhone relay host list"
	@printf "%s\n" "  rtk make device-config-verify-all Read back iPhone 17 Pro and iPhone 14 relay configs"
	@printf "%s\n" "  rtk make devices           List physical iPhones known to CoreDevice"
	@printf "%s\n" "  rtk make services          Install/start/reuse the local host service bundle"
	@printf "%s\n" "  CODEX_HOME=/tmp/codex-home rtk make services Start services against an explicit Codex home"
	@printf "%s\n" "  rtk make app-server        Legacy alias for the Dock relay service"
	@printf "%s\n" "  rtk make dock-relay        Compatibility alias for the host service bundle"
	@printf "%s\n" "  rtk make app-server-status Legacy alias for Dock relay service status"
	@printf "%s\n" "  rtk make dock-relay-status Check host service bundle status"
	@printf "%s\n" "  rtk make relay-doctor     Print relay-focused redacted diagnostics"
	@printf "%s\n" "  rtk make relay-debug-bundle Fetch the relay route-health debug bundle"
	@printf "%s\n" "  rtk make relay-host-compare HOSTS=host:port,host:port Compare route health across relays"
	@printf "%s\n" "  rtk make sim-debug-bundle SIM='iPhone 14' Copy app-owned diagnostics from simulator"
	@printf "%s\n" "  rtk make device-debug-bundle DEVICE=<UDID> Copy app-owned diagnostics from a physical iPhone"
	@printf "%s\n" "  rtk make app-server-env    Legacy alias for app-facing relay host env"
	@printf "%s\n" "  rtk make host-service-doctor Print redacted host service diagnostics"
	@printf "%s\n" "  rtk make sim-logs SIM='iPhone 17' Stream Codex Dock simulator logs"
	@printf "%s\n" "  rtk make device-logs DEVICE=<UDID> Collect Codex Dock device logarchive"
	@printf "%s\n" "  rtk make dock-relay-logs   Tail structured Dock relay stderr logs"
	@printf "%s\n" "  rtk make sims              List available simulators"
	@printf "%s\n" "  rtk make sim SIM='iPhone 17' Boot/open a simulator by name"
	@printf "%s\n" "  rtk make sim SIM=<UDID>    Boot/open a simulator by ID"

contract-generate:
	@rtk npm run contract:generate

contract-check:
	@rtk npm run contract:check

services: host-service-install host-service-start host-service-wait

env-file:
	@rtk sh -c 'set -eu; case "$(ENV_FILE)" in .env|./.env) echo "refusing to overwrite user-owned .env; set ENV_FILE to a generated path under $(APP_SERVER_DIR)" >&2; exit 2;; esac; openai_key="$${OPENAI_API_KEY:-}"; if [ -z "$$openai_key" ] && [ -f "$(USER_ENV_FILE)" ]; then openai_key="$$(awk -F= '\''$$1=="OPENAI_API_KEY"{sub(/^[^=]*=/,""); print; exit}'\'' "$(USER_ENV_FILE)")"; fi; dir="$$(dirname "$(ENV_FILE)")"; mkdir -p "$$dir"; umask 077; tmp="$$(mktemp "$$dir/.service-env.XXXXXX")"; trap '\''rm -f "$$tmp"'\'' EXIT; { echo "CODEX_DOCK_HOSTS=$(CODEX_DOCK_HOSTS)"; echo "CODEX_DOCK_REAL_HOST_ID=$(CODEX_DOCK_REAL_HOST_ID)"; echo "CODEX_DOCK_REAL_HOST_NAME=$(CODEX_DOCK_REAL_HOST_NAME)"; echo "CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL=$(CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL)"; echo "CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY=$(CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY)"; if [ -n "$$openai_key" ]; then echo "OPENAI_API_KEY=$$openai_key"; fi; } > "$$tmp"; mv "$$tmp" "$(ENV_FILE)"; trap - EXIT; echo "wrote generated service env $(ENV_FILE); left $(USER_ENV_FILE) untouched"'

node-deps:
	@rtk sh -c 'set -eu; if [ ! -d node_modules/ws ]; then npm ci; else echo "node dependencies already installed"; fi'

host-service-install: env-file node-deps
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" install $(HOST_SERVICE_ARGS)

host-service-start:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" start $(HOST_SERVICE_ARGS)

host-service-status:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" status $(HOST_SERVICE_ARGS)

host-service-wait:
	@rtk sh -c 'set -eu; mkdir -p "$(APP_SERVER_ABS_DIR)"; status="$(HOST_SERVICE_STATUS_FILE)"; for _ in $$(seq 1 $(HOST_SERVICE_WAIT_ATTEMPTS)); do if rtk node -- "$(HOST_SERVICE_SCRIPT)" status $(HOST_SERVICE_ARGS) > "$$status"; then cat "$$status"; exit 0; fi; sleep 1; done; rtk node -- "$(HOST_SERVICE_SCRIPT)" status $(HOST_SERVICE_ARGS); exit 1'

host-service-stop:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" stop $(HOST_SERVICE_ARGS)

host-service-restart:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" restart $(HOST_SERVICE_ARGS)
	@rtk make host-service-wait

host-service-logs:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" logs $(HOST_SERVICE_ARGS)

host-service-doctor:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" doctor $(HOST_SERVICE_ARGS)

app-server: services

dock-relay: services

app-server-status: host-service-status

dock-relay-status: host-service-status

app-server-env:
	@rtk node -- "$(HOST_SERVICE_SCRIPT)" app-config --format env $(HOST_SERVICE_ARGS)

app-server-stop: host-service-stop

dock-relay-stop: host-service-stop

app-server-restart: host-service-restart

dock-relay-restart: host-service-restart

relay-doctor: host-service-doctor

relay-debug-bundle: services
	@rtk node -- scripts/dock-relay-diagnostics.mjs relay-debug-bundle --host "$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)" --output "$(RELAY_DEBUG_BUNDLE)"

relay-host-compare:
	@rtk node -- scripts/dock-relay-diagnostics.mjs relay-host-compare --hosts "$(HOSTS)" --output "$(RELAY_HOST_COMPARE_REPORT)"

sim-debug-bundle:
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; if ! data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null)"; then echo "missing simulator app data container for $(SIM) ($(APP_BUNDLE_ID)); install the app first with: rtk make app SIM='\''$(SIM)'\''" >&2; exit 2; fi; source="$$data/Library/Application Support/CodexDock/Diagnostics"; output="$(SIM_DEBUG_BUNDLE_DIR)"; mkdir -p "$$output"; if [ ! -d "$$source" ]; then echo "missing simulator diagnostics directory $$source" >&2; exit 2; fi; cp -R "$$source" "$$output/CodexDock-Diagnostics"; echo "wrote $$output"'

device-debug-bundle:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; output="$(DEVICE_DEBUG_BUNDLE_DIR)"; mkdir -p "$$output"; log_dir="$(APP_BUILD_LOG_DIR)"; copy_log="$$log_dir/device-debug-bundle-$(APP_BUILD_NUMBER)-$$device.log"; mkdir -p "$$log_dir"; if ! xcrun devicectl device copy from --device "$$device" --domain-type appDataContainer --domain-identifier "$(APP_BUNDLE_ID)" --source "Library/Application Support/CodexDock/Diagnostics" --destination "$$output" > "$$copy_log" 2>&1; then echo "device debug bundle copy failed; see $$copy_log" >&2; tail -n 80 "$$copy_log" >&2; exit 1; fi; echo "wrote $$output"'

app-server-logs:
	@rtk make dock-relay-logs

dock-relay-logs:
	@rtk tail -n 200 -f "$(DOCK_RELAY_ERR_LOG)"

sim-logs:
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; xcrun simctl spawn "$$udid" log stream --style "$(LOG_STYLE)" --level debug --predicate '\''$(LOG_PREDICATE)'\'''

device-logs:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; output="$(DEVICE_LOG_OUTPUT)"; mkdir -p "$$(dirname "$$output")"; xcrun log collect --device-udid "$$device" --last "$(LOG_LAST)" --predicate '\''$(LOG_PREDICATE)'\'' --output "$$output"; echo "wrote $$output"'

app: services
	@rtk sh -c 'set -eu; python3 scripts/sim.py boot "$(SIM)"; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; if [ "$(FORCE_LAUNCH)" != "1" ] && python3 scripts/sim.py app-running "$(SIM)" "$(APP_BUNDLE_ID)" >/dev/null; then echo "$(APP_BUNDLE_ID) is already running on simulator $$udid; skipped build/install/launch. Use FORCE_LAUNCH=1 to replace it."; exit 0; fi; python3 scripts/sim.py terminate-others "$(SIM)" "$(APP_BUNDLE_ID)"; rtk xcodegen generate --spec project.yml; host_env="$(HOST_ENV_FILE)"; log_dir="$(APP_BUILD_LOG_DIR)"; build_log="$$log_dir/app-sim-build-$(APP_BUILD_NUMBER).log"; install_log="$$log_dir/app-sim-install-$(APP_BUILD_NUMBER).log"; mkdir -p "$$log_dir"; if [ ! -f "$$host_env" ]; then echo "missing generated app host env $$host_env" >&2; exit 2; fi; action="build"; if [ "$(APP_FRESH_BUILD)" = "1" ]; then action="clean build"; fi; echo "building $(APP_SCHEME) for simulator $$udid build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" $$action CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then echo "simulator build failed; see $$build_log" >&2; tail -n 80 "$$build_log" >&2; exit 1; fi; echo "installing simulator build $(APP_BUILD_NUMBER)"; if ! xcrun simctl install "$$udid" "$(APP_PATH)" > "$$install_log" 2>&1; then echo "simulator install failed; see $$install_log" >&2; tail -n 80 "$$install_log" >&2; exit 1; fi; installed_app="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" app)"; installed_build="$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$$installed_app/Info.plist")"; if [ "$$installed_build" != "$(APP_BUILD_NUMBER)" ]; then echo "installed simulator build $$installed_build did not match expected $(APP_BUILD_NUMBER)" >&2; exit 1; fi; launch_hosts=""; while IFS= read -r line || [ -n "$$line" ]; do case "$$line" in ""|\#*) continue;; esac; case "$$line" in *=*) key="$${line%%=*}"; value="$${line#*=}";; *) continue;; esac; case "$$key" in CODEX_DOCK_*) export "SIMCTL_CHILD_$$key=$$value";; *) continue;; esac; if [ "$$key" = CODEX_DOCK_HOSTS ]; then launch_hosts="$$value"; fi; done < "$$host_env"; case "$(SIM_LAUNCH_HOSTS)" in "") ;; *) launch_hosts="$(SIM_LAUNCH_HOSTS)"; export SIMCTL_CHILD_CODEX_DOCK_HOSTS="$$launch_hosts" ;; esac; profiling_enabled=false; case "$(SIM_PERFORMANCE_PROFILING)" in 1|true|TRUE|yes|YES|on|ON) profiling_enabled=true; export SIMCTL_CHILD_CODEX_DOCK_PERFORMANCE_PROFILING=1 ;; esac; echo "launch host env: $$host_env"; echo "launch hosts: $$launch_hosts"; echo "sim performance profiling: $$profiling_enabled"; xcrun simctl launch --terminate-running-process "$$udid" "$(APP_BUNDLE_ID)" > "$$install_log" 2>&1; echo "launched $(APP_BUNDLE_ID) on simulator $$udid build $(APP_BUILD_NUMBER)"'

app-test: services
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; app_data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null || true)"; log_dir="$(APP_BUILD_LOG_DIR)"; test_log="$$log_dir/app-test-$(APP_BUILD_NUMBER).log"; test_only_args=""; host_config="/tmp/codex-client/codex-dock-app-test-config.json"; sim_config="/tmp/codex-client/codex-dock-sim-ui-dump-config.json"; if [ -n "$(APP_TEST_ONLY)" ]; then test_only_args="-only-testing:$(APP_TEST_ONLY)"; fi; mkdir -p "$$log_dir" /tmp/codex-client; rtk python3 -c "import datetime,json,sys; config,sim_name,udid,bundle_id,app_data,build=sys.argv[1:]; expires=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=10)).replace(microsecond=0).isoformat().replace(\"+00:00\",\"Z\"); payload={\"jsonPath\":\"/tmp/codex-client/codex-dock-app-test-dump.json\",\"markdownPath\":\"/tmp/codex-client/codex-dock-app-test-dump.md\",\"simulatorName\":sim_name,\"simulatorUDID\":udid,\"appBundleID\":bundle_id,\"appDataContainer\":app_data or None,\"configuredBuildNumber\":build or None,\"expectedScreen\":None,\"expectedThreadID\":None,\"expiresAt\":expires}; open(config,\"w\").write(json.dumps(payload)+\"\\n\")" "$$host_config" "$(SIM)" "$$udid" "$(APP_BUNDLE_ID)" "$$app_data" "$(APP_BUILD_NUMBER)"; xcrun simctl spawn "$$udid" /bin/mkdir -p /tmp/codex-client; xcrun simctl spawn "$$udid" /bin/sh -c "/bin/cat > $$sim_config" < "$$host_config"; echo "testing $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; if ! CODEX_DOCK_UI_TEST_HOSTS="$(CODEX_DOCK_UI_TEST_HOSTS)" SIMULATOR_HOST_HOME="$$HOME" CODEX_DOCK_UI_TEST_SIMULATOR_UDID="$$udid" CODEX_DOCK_UI_TEST_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER="$$app_data" CODEX_DOCK_SIM_UI_SYNC_OUT="$(CODEX_DOCK_SIM_UI_SYNC_OUT)" CODEX_DOCK_SIM_UI_SYNC_DURATION_MS="$(CODEX_DOCK_SIM_UI_SYNC_DURATION_MS)" CODEX_DOCK_SIM_UI_SYNC_SAMPLE_MS="$(CODEX_DOCK_SIM_UI_SYNC_SAMPLE_MS)" xcodebuild -quiet test -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" $$test_only_args > "$$test_log" 2>&1; then echo "app test failed; see $$test_log" >&2; tail -n 80 "$$test_log" >&2; exit 1; fi; echo "tested $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"'

sim-ui-dump:
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; output_dir="$(SIM_UI_DUMP_DIR)"; json_path="$(SIM_UI_DUMP_JSON)"; markdown_path="$(SIM_UI_DUMP_MD)"; host_config="$$output_dir/sim-ui-dump-config.json"; sim_config="/tmp/codex-client/codex-dock-sim-ui-dump-config.json"; sim_json="/tmp/codex-client/codex-dock-sim-ui-dump.json"; sim_markdown="/tmp/codex-client/codex-dock-sim-ui-dump.md"; log_dir="$(APP_BUILD_LOG_DIR)"; build_log="$$log_dir/sim-ui-dump-build-$(APP_BUILD_NUMBER).log"; test_log="$$log_dir/sim-ui-dump-test-$(APP_BUILD_NUMBER).log"; mkdir -p "$$output_dir" "$$log_dir"; installed_app="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" app 2>/dev/null || true)"; app_data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null || true)"; installed_build=""; if [ -n "$$installed_app" ]; then installed_build="$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$$installed_app/Info.plist" 2>/dev/null || true)"; fi; rtk python3 -c "import datetime,json,sys; config,json_path,markdown_path,sim_name,udid,bundle_id,app_data,build,expected_screen,expected_thread=sys.argv[1:]; expires=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=10)).replace(microsecond=0).isoformat().replace(\"+00:00\",\"Z\"); payload={\"jsonPath\":json_path,\"markdownPath\":markdown_path,\"simulatorName\":sim_name,\"simulatorUDID\":udid,\"appBundleID\":bundle_id,\"appDataContainer\":app_data or None,\"configuredBuildNumber\":build or None,\"expectedScreen\":expected_screen or None,\"expectedThreadID\":expected_thread or None,\"expiresAt\":expires}; open(config,\"w\").write(json.dumps(payload)+\"\\n\")" "$$host_config" "$$sim_json" "$$sim_markdown" "$(SIM)" "$$udid" "$(APP_BUNDLE_ID)" "$$app_data" "$$installed_build" "$(EXPECTED_SCREEN)" "$(EXPECTED_THREAD_ID)"; xcrun simctl spawn "$$udid" /bin/mkdir -p /tmp/codex-client; xcrun simctl spawn "$$udid" /bin/sh -c "/bin/cat > $$sim_config" < "$$host_config"; cleanup() { xcrun simctl spawn "$$udid" /bin/rm -f "$$sim_config" "$$sim_json" "$$sim_markdown" >/dev/null 2>&1 || true; }; copy_artifact() { sim_path="$$1"; host_path="$$2"; tmp="$$host_path.tmp"; if xcrun simctl spawn "$$udid" /bin/cat "$$sim_path" > "$$tmp" 2>/dev/null; then mv "$$tmp" "$$host_path"; return 0; fi; rm -f "$$tmp"; return 1; }; trap cleanup EXIT INT TERM; echo "building simulator UI dump test for $(APP_SCHEME) on simulator $$udid"; if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then echo "sim UI dump build failed; see $$build_log" >&2; tail -n 80 "$$build_log" >&2; exit 1; fi; echo "dumping current simulator UI state to $$json_path"; if ! CODEX_DOCK_CURRENT_UI_DUMP_REQUIRE_CONFIG=1 SIMULATOR_HOST_HOME="$$HOME" CODEX_DOCK_UI_TEST_SIMULATOR_UDID="$$udid" CODEX_DOCK_UI_TEST_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER="$$app_data" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockCurrentUIDumpTests/testDumpsCurrentVisibleScreenOnce > "$$test_log" 2>&1; then echo "sim UI dump failed; see $$test_log" >&2; tail -n 120 "$$test_log" >&2; copy_artifact "$$sim_json" "$$json_path" || true; copy_artifact "$$sim_markdown" "$$markdown_path" || true; if [ -f "$$json_path" ]; then rtk node scripts/check-proof-report-contracts.mjs "$$json_path"; echo "wrote $$json_path"; fi; if [ -f "$$markdown_path" ]; then echo "wrote $$markdown_path"; fi; exit 1; fi; if ! copy_artifact "$$sim_json" "$$json_path"; then echo "sim UI dump did not produce $$sim_json" >&2; exit 1; fi; if ! copy_artifact "$$sim_markdown" "$$markdown_path"; then echo "sim UI dump did not produce $$sim_markdown" >&2; exit 1; fi; echo "wrote $$json_path"; echo "wrote $$markdown_path"'
	@rtk node scripts/check-proof-report-contracts.mjs "$(SIM_UI_DUMP_JSON)"

sim-ui-client-rename-proof:
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c '\
		set -eu; \
		udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; \
		output_dir="$(SIM_UI_CLIENT_RENAME_DIR)"; \
		mkdir -p "$$output_dir" "$(APP_BUILD_LOG_DIR)"; \
		fixture_ready="$$output_dir/client-rename-fixture-ready.json"; \
		ui_result="$$output_dir/client-rename-latency-ui.json"; \
		fixture_stop="$$output_dir/client-rename-fixture-stop"; \
		report_json="$$output_dir/client-rename-latency.json"; \
		report_md="$$output_dir/client-rename-latency.md"; \
		sim_ready_host="$$output_dir/client-rename-fixture-ready-simulator.json"; \
		host_ready="/tmp/codex-client/codex-dock-client-rename-proof-ready.json"; \
		sim_ready="/tmp/codex-client/codex-dock-client-rename-proof-ready.json"; \
		sim_ui_result="/tmp/codex-client/codex-dock-client-rename-latency-ui.json"; \
		build_log="$(APP_BUILD_LOG_DIR)/sim-ui-client-rename-build-$(APP_BUILD_NUMBER).log"; \
		test_log="$(APP_BUILD_LOG_DIR)/sim-ui-client-rename-test-$(APP_BUILD_NUMBER).log"; \
		fixture_log="$$output_dir/client-rename-fixture.out.log"; \
		rm -f "$$fixture_ready" "$$ui_result" "$$fixture_stop" "$$report_json" "$$report_md" "$$sim_ready_host" "$$host_ready"; \
		xcrun simctl spawn "$$udid" /bin/rm -f "$$sim_ready" "$$sim_ui_result" >/dev/null 2>&1 || true; \
		echo "resetting simulator app data for client rename latency proof"; \
		xcrun simctl uninstall "$$udid" "$(APP_BUNDLE_ID)" >/dev/null 2>&1 || true; \
		echo "building client rename latency proof test for $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; \
		if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then \
			echo "client rename proof build failed; see $$build_log" >&2; \
			tail -n 80 "$$build_log" >&2; \
			exit 1; \
		fi; \
		fixture_pid=""; \
		cleanup() { \
			status="$${1:-$$?}"; \
			touch "$$fixture_stop" 2>/dev/null || true; \
			rm -f "$$host_ready"; \
			xcrun simctl spawn "$$udid" /bin/rm -f "$$sim_ready" "$$sim_ui_result" >/dev/null 2>&1 || true; \
			if [ -n "$${fixture_pid:-}" ] && kill -0 "$$fixture_pid" 2>/dev/null; then \
				kill "$$fixture_pid" 2>/dev/null || true; \
				wait "$$fixture_pid" 2>/dev/null || true; \
			fi; \
			exit "$$status"; \
		}; \
			copy_sim_ui_result() { \
				if [ -f "$$ui_result" ]; then return 0; fi; \
				tmp="$$ui_result.tmp"; \
				for candidate in "$$sim_ui_result" "$$ui_result"; do \
					if xcrun simctl spawn "$$udid" /bin/cat "$$candidate" > "$$tmp" 2>/dev/null; then \
						mv "$$tmp" "$$ui_result"; \
						return 0; \
					fi; \
				done; \
				rm -f "$$tmp"; \
				return 1; \
			}; \
		trap cleanup INT TERM; \
		echo "starting client rename latency fixture"; \
		rtk node scripts/dock-relay-client-rename-latency-fixture.mjs --ready-out "$$fixture_ready" --ui-result-in "$$ui_result" --stop-in "$$fixture_stop" --json-out "$$report_json" --summary-out "$$report_md" --server-ack-delay-ms "$(SIM_UI_CLIENT_RENAME_SERVER_ACK_DELAY_MS)" --ui-budget-ms "$(SIM_UI_CLIENT_RENAME_UI_BUDGET_MS)" --wait-timeout-ms "$(SIM_UI_SYNC_READY_TIMEOUT_MS)" > "$$fixture_log" 2>&1 & \
		fixture_pid="$$!"; \
		deadline=$$(( $$(date +%s) + ( $(SIM_UI_SYNC_READY_TIMEOUT_MS) / 1000 ) )); \
		while [ ! -f "$$fixture_ready" ]; do \
			if ! kill -0 "$$fixture_pid" 2>/dev/null; then \
				echo "client rename fixture exited before ready; see $$fixture_log" >&2; \
				tail -n 120 "$$fixture_log" >&2; \
				cleanup 1; \
			fi; \
			if [ "$$(date +%s)" -gt "$$deadline" ]; then \
				echo "client rename fixture did not become ready; see $$fixture_log" >&2; \
				tail -n 120 "$$fixture_log" >&2; \
				cleanup 1; \
			fi; \
			sleep 0.2; \
		done; \
		cp "$$fixture_ready" "$$host_ready"; \
		rtk python3 -c "import json,sys; data=json.load(open(sys.argv[1])); data[\"uiResultPath\"]=sys.argv[3]; open(sys.argv[2],\"w\").write(json.dumps(data)+\"\\n\")" "$$fixture_ready" "$$sim_ready_host" "$$sim_ui_result"; \
		xcrun simctl spawn "$$udid" /bin/mkdir -p /tmp/codex-client; \
		xcrun simctl spawn "$$udid" /bin/sh -c "/bin/cat > $$sim_ready" < "$$sim_ready_host"; \
		echo "running controlled client rename latency UI test on $(SIM)"; \
		test_status=0; \
			if ! CODEX_DOCK_CLIENT_RENAME_PROOF_UI_RESULT_HOST="$$ui_result" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockThreadRenameUITests/testControlledClientRenameIsOptimisticWhenConfigured > "$$test_log" 2>&1; then \
				test_status=1; \
			fi; \
		copy_sim_ui_result || true; \
		touch "$$fixture_stop"; \
		fixture_status=0; \
		if ! wait "$$fixture_pid"; then fixture_status=1; fi; \
		fixture_pid=""; \
		trap - INT TERM; \
		rm -f "$$host_ready"; \
		xcrun simctl spawn "$$udid" /bin/rm -f "$$sim_ready" "$$sim_ui_result" >/dev/null 2>&1 || true; \
		if [ "$$test_status" -ne 0 ]; then \
			echo "client rename latency UI test failed; see $$test_log" >&2; \
			tail -n 120 "$$test_log" >&2; \
			if [ -f "$$ui_result" ]; then echo "wrote $$ui_result"; fi; \
			if [ -f "$$report_json" ]; then echo "wrote $$report_json"; fi; \
			exit 1; \
		fi; \
		if [ "$$fixture_status" -ne 0 ]; then \
			echo "client rename latency fixture failed; see $$fixture_log" >&2; \
			tail -n 120 "$$fixture_log" >&2; \
			if [ -f "$$ui_result" ]; then echo "wrote $$ui_result"; fi; \
			if [ -f "$$report_json" ]; then echo "wrote $$report_json"; fi; \
			exit 1; \
		fi; \
		echo "wrote $$ui_result"; \
		echo "wrote $$report_json"; \
		echo "wrote $$report_md"'

sim-ui-user-message-latency-proof:
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c '\
		set -eu; \
		udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; \
		output_dir="$(SIM_UI_USER_MESSAGE_DIR)"; \
		mkdir -p "$$output_dir" "$(APP_BUILD_LOG_DIR)"; \
		fixture_ready="$$output_dir/user-message-fixture-ready.json"; \
		ui_result="$$output_dir/user-message-latency-ui.json"; \
		fixture_stop="$$output_dir/user-message-fixture-stop"; \
		report_json="$$output_dir/user-message-latency.json"; \
		report_md="$$output_dir/user-message-latency.md"; \
		host_ready="/tmp/codex-client/codex-dock-user-message-proof-ready.json"; \
		host_ui_result="/tmp/codex-client/codex-dock-user-message-latency-ui.json"; \
		build_log="$(APP_BUILD_LOG_DIR)/sim-ui-user-message-build-$(APP_BUILD_NUMBER).log"; \
		test_log="$(APP_BUILD_LOG_DIR)/sim-ui-user-message-test-$(APP_BUILD_NUMBER).log"; \
		fixture_log="$$output_dir/user-message-fixture.out.log"; \
		rm -f "$$fixture_ready" "$$ui_result" "$$fixture_stop" "$$report_json" "$$report_md" "$$host_ready" "$$host_ui_result"; \
		echo "resetting simulator app data for user-message latency proof"; \
		xcrun simctl uninstall "$$udid" "$(APP_BUNDLE_ID)" >/dev/null 2>&1 || true; \
		echo "building user-message latency proof test for $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; \
		if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then \
			echo "user-message proof build failed; see $$build_log" >&2; \
			tail -n 80 "$$build_log" >&2; \
			exit 1; \
		fi; \
		fixture_pid=""; \
		cleanup() { \
			status="$${1:-$$?}"; \
			touch "$$fixture_stop" 2>/dev/null || true; \
			if [ -n "$${fixture_pid:-}" ] && kill -0 "$$fixture_pid" 2>/dev/null; then \
				kill "$$fixture_pid" 2>/dev/null || true; \
				wait "$$fixture_pid" 2>/dev/null || true; \
			fi; \
			rm -f "$$host_ready" "$$host_ui_result"; \
			exit "$$status"; \
		}; \
		trap cleanup INT TERM; \
		echo "starting user-message latency fixture"; \
		rtk node scripts/dock-relay-user-message-latency-fixture.mjs --ready-out "$$fixture_ready" --ui-result-in "$$ui_result" --stop-in "$$fixture_stop" --json-out "$$report_json" --summary-out "$$report_md" --upstream-ack-delay-ms "$(SIM_UI_USER_MESSAGE_UPSTREAM_ACK_DELAY_MS)" --ui-budget-ms "$(SIM_UI_USER_MESSAGE_UI_BUDGET_MS)" --wait-timeout-ms "$(SIM_UI_USER_MESSAGE_WAIT_TIMEOUT_MS)" > "$$fixture_log" 2>&1 & \
		fixture_pid="$$!"; \
		deadline=$$(( $$(date +%s) + ( $(SIM_UI_SYNC_READY_TIMEOUT_MS) / 1000 ) )); \
		while [ ! -f "$$fixture_ready" ]; do \
			if ! kill -0 "$$fixture_pid" 2>/dev/null; then \
				echo "user-message fixture exited before ready; see $$fixture_log" >&2; \
				tail -n 120 "$$fixture_log" >&2; \
				cleanup 1; \
			fi; \
			if [ "$$(date +%s)" -gt "$$deadline" ]; then \
				echo "user-message fixture did not become ready; see $$fixture_log" >&2; \
				tail -n 120 "$$fixture_log" >&2; \
				cleanup 1; \
			fi; \
			sleep 0.2; \
		done; \
		cp "$$fixture_ready" "$$host_ready"; \
		echo "running controlled user-message latency UI test on $(SIM)"; \
		test_status=0; \
		if ! CODEX_DOCK_USER_MESSAGE_PROOF_READY="$$fixture_ready" CODEX_DOCK_USER_MESSAGE_PROOF_UI_RESULT_HOST="$$ui_result" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockUserMessageLatencyUITests/testControlledUserMessageSendIsNonBlockingWhenConfigured > "$$test_log" 2>&1; then \
			test_status=1; \
		fi; \
		touch "$$fixture_stop"; \
		fixture_status=0; \
		if ! wait "$$fixture_pid"; then fixture_status=1; fi; \
		fixture_pid=""; \
		trap - INT TERM; \
		rm -f "$$host_ready" "$$host_ui_result"; \
		if [ "$$test_status" -ne 0 ]; then \
			echo "user-message latency UI test failed; see $$test_log" >&2; \
			tail -n 120 "$$test_log" >&2; \
			if [ -f "$$ui_result" ]; then echo "wrote $$ui_result"; fi; \
			if [ -f "$$report_json" ]; then echo "wrote $$report_json"; fi; \
			exit 1; \
		fi; \
		if [ "$$fixture_status" -ne 0 ]; then \
			echo "user-message latency fixture failed; see $$fixture_log" >&2; \
			tail -n 120 "$$fixture_log" >&2; \
			if [ -f "$$ui_result" ]; then echo "wrote $$ui_result"; fi; \
			if [ -f "$$report_json" ]; then echo "wrote $$report_json"; fi; \
			exit 1; \
		fi; \
		echo "wrote $$ui_result"; \
		echo "wrote $$report_json"; \
		echo "wrote $$report_md"'

sim-ui-sync-proof: services
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; app_data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null || true)"; output_dir="$(SIM_UI_SYNC_DIR)"; mkdir -p "$$output_dir" "$(APP_BUILD_LOG_DIR)"; relay_json="$$output_dir/relay-client-path.json"; relay_md="$$output_dir/relay-client-path.md"; ui_samples="$$output_dir/ui-samples.jsonl"; ready_file="$$output_dir/ui-ready.json"; report_json="$$output_dir/simulator-ui-sync.json"; report_md="$$output_dir/simulator-ui-sync.md"; build_log="$(APP_BUILD_LOG_DIR)/sim-ui-sync-build-$(APP_BUILD_NUMBER).log"; test_log="$(APP_BUILD_LOG_DIR)/sim-ui-sync-test-$(APP_BUILD_NUMBER).log"; relay_log="$$output_dir/relay-client-path.out.log"; config="/tmp/codex-client/codex-dock-sim-ui-sync-config.json"; config_lock="/tmp/codex-client/codex-dock-sim-ui-sync-config.lock"; write_blocked_proof() { reason="$$1"; if [ ! -s "$$relay_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind relay-sync-audit --json-out "$$relay_json" --summary-out "$$relay_md" --reason "$$reason" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" || true; fi; if [ ! -s "$$report_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind sim-ui-sync --json-out "$$report_json" --summary-out "$$report_md" --reason "$$reason" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" --relay-report "$$relay_json" || true; fi; }; blocked_reason="sim UI sync proof stopped before reports were generated"; if ! mkdir "$$config_lock" 2>/dev/null; then blocked_reason="another simulator UI sync proof is already using $$config"; echo "$$blocked_reason" >&2; write_blocked_proof "$$blocked_reason"; exit 1; fi; rtk python3 -c "import datetime,json,sys; expires=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=10)).replace(microsecond=0).isoformat().replace(\"+00:00\",\"Z\"); open(sys.argv[1],\"w\").write(json.dumps({\"outputPath\":sys.argv[2],\"hosts\":sys.argv[3],\"durationMS\":int(sys.argv[4]),\"sampleMS\":int(sys.argv[5]),\"readyPath\":sys.argv[6],\"checkpointSweep\":sys.argv[7]==\"1\",\"dockLenses\":[value for value in sys.argv[8].split(\",\") if value],\"expiresAt\":expires})+\"\\n\")" "$$config" "$$ui_samples" "$(SIM_UI_SYNC_HOSTS)" "$(SIM_UI_SYNC_DURATION_MS)" "$(SIM_UI_SYNC_SAMPLE_MS)" "$$ready_file" "$(SIM_UI_SYNC_CHECKPOINT_SWEEP)" "$(SIM_UI_SYNC_LENSES)"; rtk node scripts/sim-ui-sync-config.mjs annotate --path "$$config" --simulator-udid "$$udid" --app-bundle-id "$(APP_BUNDLE_ID)" --app-data-container "$$app_data"; echo "building displayed UI sync proof test for $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then blocked_reason="sim UI sync build failed; see $$build_log"; echo "$$blocked_reason" >&2; tail -n 80 "$$build_log" >&2; write_blocked_proof "$$blocked_reason"; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; exit 1; fi; echo "writing simulator UI sync proof to $$output_dir"; rtk node scripts/dock-relay-sync-audit.mjs --relay-url "$(SIM_UI_SYNC_RELAY_WS)" $(SIM_UI_SYNC_CODEX_HOME_ARG) --mode soak --client-path-only --force-dock-resync --duration-ms "$(SIM_UI_SYNC_RELAY_DURATION_MS)" --sample-interval-ms "$(SIM_UI_SYNC_RELAY_SAMPLE_MS)" --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms "$(MAX_UI_LAG_MS)" --detail "$(SIM_UI_SYNC_RELAY_DETAIL)" --detail-limit "$(SIM_UI_SYNC_RELAY_DETAIL_LIMIT)" --detail-observe-ms "$(SIM_UI_SYNC_RELAY_DETAIL_OBSERVE_MS)" --json-out "$$relay_json" --summary-out "$$relay_md" --summary-only > "$$relay_log" 2>&1 & relay_pid="$$!"; cleanup() { status="$${1:-$$?}"; if [ "$$status" -ne 0 ]; then write_blocked_proof "$$blocked_reason"; fi; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; if kill -0 "$$relay_pid" 2>/dev/null; then kill "$$relay_pid" 2>/dev/null || true; wait "$$relay_pid" 2>/dev/null || true; fi; exit "$$status"; }; trap cleanup INT TERM; echo "running displayed UI sampler on $(SIM) with hosts=$(SIM_UI_SYNC_HOSTS)"; if ! SIMULATOR_HOST_HOME="$$HOME" CODEX_DOCK_UI_TEST_SIMULATOR_UDID="$$udid" CODEX_DOCK_UI_TEST_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER="$$app_data" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockDisplayedSyncProofTests/testSamplesRelayBackedDockDisplayOverTime > "$$test_log" 2>&1; then blocked_reason="sim UI sync test failed; see $$test_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$test_log" >&2; cleanup 1; fi; echo "waiting for relay sync audit recorder"; wait "$$relay_pid" || { blocked_reason="relay sync audit recorder failed; see $$relay_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$relay_log" >&2; write_blocked_proof "$$blocked_reason"; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; exit 1; }; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; trap - INT TERM; rtk node scripts/dock-relay-simulator-ui-sync-proof.mjs --relay-report "$$relay_json" --ui-samples "$$ui_samples" --max-ui-lag-ms "$(MAX_UI_LAG_MS)" --json-out "$$report_json" --summary-out "$$report_md" --fail-on-diff; echo "wrote $$report_json"; echo "wrote $$report_md"'

sim-ui-scenario-sync-proof: services
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; app_data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null || true)"; output_dir="$(SIM_UI_SYNC_DIR)"; mkdir -p "$$output_dir" "$(APP_BUILD_LOG_DIR)"; relay_json="$$output_dir/relay-client-path.json"; relay_md="$$output_dir/relay-client-path.md"; ui_samples="$$output_dir/ui-samples.jsonl"; ready_file="$$output_dir/ui-ready.json"; report_json="$$output_dir/simulator-ui-sync.json"; report_md="$$output_dir/simulator-ui-sync.md"; build_log="$(APP_BUILD_LOG_DIR)/sim-ui-scenario-sync-build-$(APP_BUILD_NUMBER).log"; test_log="$(APP_BUILD_LOG_DIR)/sim-ui-scenario-sync-test-$(APP_BUILD_NUMBER).log"; relay_log="$$output_dir/relay-client-path.out.log"; config="/tmp/codex-client/codex-dock-sim-ui-sync-config.json"; config_lock="/tmp/codex-client/codex-dock-sim-ui-sync-config.lock"; write_blocked_proof() { reason="$$1"; if [ ! -s "$$relay_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind relay-sync-audit --json-out "$$relay_json" --summary-out "$$relay_md" --reason "$$reason" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" || true; fi; if [ ! -s "$$report_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind sim-ui-sync --json-out "$$report_json" --summary-out "$$report_md" --reason "$$reason" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" --relay-report "$$relay_json" || true; fi; }; blocked_reason="sim UI scenario proof stopped before reports were generated"; if ! mkdir "$$config_lock" 2>/dev/null; then blocked_reason="another simulator UI sync proof is already using $$config"; echo "$$blocked_reason" >&2; write_blocked_proof "$$blocked_reason"; exit 1; fi; rm -f "$$ready_file"; rtk python3 -c "import datetime,json,sys; expires=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=10)).replace(microsecond=0).isoformat().replace(\"+00:00\",\"Z\"); open(sys.argv[1],\"w\").write(json.dumps({\"outputPath\":sys.argv[2],\"hosts\":sys.argv[3],\"durationMS\":int(sys.argv[4]),\"sampleMS\":int(sys.argv[5]),\"readyPath\":sys.argv[6],\"checkpointSweep\":sys.argv[7]==\"1\",\"expiresAt\":expires})+\"\\n\")" "$$config" "$$ui_samples" "$(SIM_UI_SYNC_HOSTS)" "$(SIM_UI_SYNC_DURATION_MS)" "$(SIM_UI_SYNC_SAMPLE_MS)" "$$ready_file" "$(SIM_UI_SYNC_CHECKPOINT_SWEEP)"; rtk node scripts/sim-ui-sync-config.mjs annotate --path "$$config" --simulator-udid "$$udid" --app-bundle-id "$(APP_BUNDLE_ID)" --app-data-container "$$app_data"; echo "building displayed UI scenario proof test for $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then blocked_reason="sim UI scenario build failed; see $$build_log"; echo "$$blocked_reason" >&2; tail -n 80 "$$build_log" >&2; write_blocked_proof "$$blocked_reason"; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; exit 1; fi; ui_pid=""; cleanup() { status="$${1:-$$?}"; if [ "$$status" -ne 0 ]; then write_blocked_proof "$$blocked_reason"; fi; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; if [ -n "$${ui_pid:-}" ] && kill -0 "$$ui_pid" 2>/dev/null; then kill "$$ui_pid" 2>/dev/null || true; wait "$$ui_pid" 2>/dev/null || true; fi; exit "$$status"; }; trap cleanup INT TERM; echo "running displayed UI sampler on $(SIM) with hosts=$(SIM_UI_SYNC_HOSTS)"; SIMULATOR_HOST_HOME="$$HOME" CODEX_DOCK_UI_TEST_SIMULATOR_UDID="$$udid" CODEX_DOCK_UI_TEST_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER="$$app_data" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockDisplayedSyncProofTests/testSamplesRelayBackedDockDisplayOverTime > "$$test_log" 2>&1 & ui_pid="$$!"; ready_deadline=$$(( $$(date +%s) + ( $(SIM_UI_SYNC_READY_TIMEOUT_MS) / 1000 ) )); while [ ! -f "$$ready_file" ]; do if ! kill -0 "$$ui_pid" 2>/dev/null; then blocked_reason="sim UI scenario test exited before ready; see $$test_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$test_log" >&2; cleanup 1; fi; if [ "$$(date +%s)" -gt "$$ready_deadline" ]; then blocked_reason="sim UI scenario sampler did not become ready; see $$test_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$test_log" >&2; cleanup 1; fi; sleep 0.2; done; echo "running relay scenario $(SIM_UI_SYNC_SCENARIO) x$(SIM_UI_SYNC_SCENARIO_REPETITIONS) while UI sampler is active"; if ! rtk node scripts/dock-relay-sync-audit.mjs --relay-url "$(SIM_UI_SYNC_RELAY_WS)" $(SIM_UI_SYNC_CODEX_HOME_ARG) --mode scenario --scenario "$(SIM_UI_SYNC_SCENARIO)" $(SIM_UI_SYNC_SCENARIO_THREAD_ARG) --scenario-hold-ms "$(SIM_UI_SYNC_SCENARIO_HOLD_MS)" --scenario-repetitions "$(SIM_UI_SYNC_SCENARIO_REPETITIONS)" --client-path-only --detail none --dock-collection-timeout-ms 120000 --max-stream-lag-ms "$(MAX_UI_LAG_MS)" --json-out "$$relay_json" --summary-out "$$relay_md" --summary-only --fail-on-diff > "$$relay_log" 2>&1; then blocked_reason="relay scenario sync audit failed; see $$relay_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$relay_log" >&2; cleanup 1; fi; if ! wait "$$ui_pid"; then blocked_reason="sim UI scenario test failed; see $$test_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$test_log" >&2; cleanup 1; fi; ui_pid=""; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; trap - INT TERM; rtk node scripts/dock-relay-simulator-ui-sync-proof.mjs --relay-report "$$relay_json" --ui-samples "$$ui_samples" --max-ui-lag-ms "$(MAX_UI_LAG_MS)" --json-out "$$report_json" --summary-out "$$report_md" --fail-on-diff; echo "wrote $$report_json"; echo "wrote $$report_md"'

sim-ui-isolated-scenario-sync-proof:
	@rtk sh -c 'set -eu; root="$(SIM_UI_ISOLATED_ROOT)"; home="$(SIM_UI_ISOLATED_HOME)"; service_dir="$(SIM_UI_ISOLATED_SERVICE_DIR)"; metadata="$(SIM_UI_ISOLATED_METADATA)"; relay_port="$(SIM_UI_ISOLATED_RELAY_PORT)"; relay_ws="ws://127.0.0.1:$$relay_port"; relay_hosts="127.0.0.1:$$relay_port"; mkdir -p "$$root"; rtk node scripts/codex-dock-isolated-home.mjs create --source-home "$(SIM_UI_ISOLATED_SOURCE_HOME)" --output-home "$$home" --json-out "$$metadata" --max-rollout-bytes "$(SIM_UI_ISOLATED_MAX_ROLLOUT_BYTES)" --thread-count "$(SIM_UI_ISOLATED_THREAD_COUNT)" --force >/dev/null; thread_id="$$(rtk node -e '\''const fs = require("fs"); const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(data.threadID);'\'' "$$metadata")"; cleanup() { rtk make --no-print-directory host-service-stop CODEX_HOME="$$home" APP_SERVER_DIR="$$service_dir" ENV_FILE="$$service_dir/service.env" HOST_ENV_FILE="$$service_dir/host.env" DOCK_RELAY_PORT="$$relay_port" DOCK_RELAY_WS="$$relay_ws" CODEX_DOCK_HOSTS="$$relay_hosts" DOCK_RELAY_LABEL="$(SIM_UI_ISOLATED_RELAY_LABEL)" HOST_SERVICE_NETWORK_PROFILE=simulator-local >/dev/null 2>&1 || true; }; trap cleanup EXIT INT TERM; rtk make --no-print-directory sim-ui-scenario-sync-proof SIM="$(SIM)" CODEX_HOME="$$home" APP_SERVER_DIR="$$service_dir" ENV_FILE="$$service_dir/service.env" HOST_ENV_FILE="$$service_dir/host.env" DOCK_RELAY_PORT="$$relay_port" DOCK_RELAY_WS="$$relay_ws" CODEX_DOCK_HOSTS="$$relay_hosts" CODEX_DOCK_UI_TEST_HOSTS="$$relay_hosts" SIM_UI_SYNC_HOSTS="$$relay_hosts" SIM_UI_SYNC_RELAY_WS="$$relay_ws" SIM_UI_SYNC_CODEX_HOME="$$home" SIM_UI_SYNC_SCENARIO_THREAD_ID="$$thread_id" SIM_UI_SYNC_DIR="$$root/sim-ui" DOCK_RELAY_LABEL="$(SIM_UI_ISOLATED_RELAY_LABEL)" HOST_SERVICE_NETWORK_PROFILE=simulator-local MAX_UI_LAG_MS="$(MAX_UI_LAG_MS)" SIM_UI_SYNC_DURATION_MS="$(SIM_UI_SYNC_DURATION_MS)" SIM_UI_SYNC_SAMPLE_MS="$(SIM_UI_SYNC_SAMPLE_MS)" SIM_UI_SYNC_SCENARIO="$(SIM_UI_SYNC_SCENARIO)" SIM_UI_SYNC_SCENARIO_HOLD_MS="$(SIM_UI_SYNC_SCENARIO_HOLD_MS)" SIM_UI_SYNC_SCENARIO_REPETITIONS="$(SIM_UI_SYNC_SCENARIO_REPETITIONS)" SIM_UI_SYNC_READY_TIMEOUT_MS="$(SIM_UI_SYNC_READY_TIMEOUT_MS)" SIM_UI_SYNC_CHECKPOINT_SWEEP="$(SIM_UI_SYNC_CHECKPOINT_SWEEP)"; echo "wrote $$metadata"; echo "wrote $$root/sim-ui/simulator-ui-sync.json"; echo "wrote $$root/sim-ui/simulator-ui-sync.md"'

sim-ui-controlled-scenario-sync-proof:
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; app_data="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" data 2>/dev/null || true)"; output_dir="$(SIM_UI_SYNC_DIR)"; mkdir -p "$$output_dir" "$(APP_BUILD_LOG_DIR)"; relay_json="$$output_dir/relay-client-path.json"; relay_md="$$output_dir/relay-client-path.md"; ui_samples="$$output_dir/ui-samples.jsonl"; ready_file="$$output_dir/ui-ready.json"; fixture_ready="$$output_dir/fixture-ready.json"; fixture_stop="$$output_dir/fixture-stop"; report_json="$$output_dir/simulator-ui-sync.json"; report_md="$$output_dir/simulator-ui-sync.md"; build_log="$(APP_BUILD_LOG_DIR)/sim-ui-controlled-sync-build-$(APP_BUILD_NUMBER).log"; test_log="$(APP_BUILD_LOG_DIR)/sim-ui-controlled-sync-test-$(APP_BUILD_NUMBER).log"; fixture_log="$$output_dir/controlled-fixture.out.log"; config="/tmp/codex-client/codex-dock-sim-ui-sync-config.json"; config_lock="/tmp/codex-client/codex-dock-sim-ui-sync-config.lock"; write_blocked_proof() { reason="$$1"; if [ ! -s "$$relay_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind controlled-scenario --json-out "$$relay_json" --summary-out "$$relay_md" --reason "$$reason" --scenario "$(SIM_UI_SYNC_SCENARIO)" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" || true; fi; if [ ! -s "$$report_json" ]; then rtk node scripts/write-blocked-proof-report.mjs --kind sim-ui-sync --json-out "$$report_json" --summary-out "$$report_md" --reason "$$reason" --relay-url "$(SIM_UI_SYNC_RELAY_WS)" --relay-report "$$relay_json" || true; fi; }; blocked_reason="controlled simulator proof stopped before reports were generated"; if ! mkdir "$$config_lock" 2>/dev/null; then blocked_reason="another simulator UI sync proof is already using $$config"; echo "$$blocked_reason" >&2; write_blocked_proof "$$blocked_reason"; exit 1; fi; rm -f "$$ready_file" "$$fixture_ready" "$$fixture_stop"; echo "resetting simulator app data for controlled proof scenario $(SIM_UI_SYNC_SCENARIO)"; xcrun simctl uninstall "$$udid" "$(APP_BUNDLE_ID)" >/dev/null 2>&1 || true; echo "building controlled displayed UI scenario proof test for $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet build-for-testing -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then blocked_reason="controlled sim UI build failed; see $$build_log"; echo "$$blocked_reason" >&2; tail -n 80 "$$build_log" >&2; write_blocked_proof "$$blocked_reason"; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; exit 1; fi; fixture_pid=""; cleanup() { status="$${1:-$$?}"; if [ "$$status" -ne 0 ]; then write_blocked_proof "$$blocked_reason"; fi; touch "$$fixture_stop" 2>/dev/null || true; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; if [ -n "$${fixture_pid:-}" ] && kill -0 "$$fixture_pid" 2>/dev/null; then kill "$$fixture_pid" 2>/dev/null || true; wait "$$fixture_pid" 2>/dev/null || true; fi; exit "$$status"; }; trap cleanup INT TERM; echo "starting controlled simulator fixture scenario $(SIM_UI_SYNC_SCENARIO)"; rtk node scripts/dock-relay-controlled-simulator-fixture.mjs --scenario "$(SIM_UI_SYNC_SCENARIO)" --ready-out "$$fixture_ready" --ui-ready-in "$$ready_file" --stop-in "$$fixture_stop" --json-out "$$relay_json" --summary-out "$$relay_md" --scenario-hold-ms "$(SIM_UI_SYNC_SCENARIO_HOLD_MS)" --dock-collection-timeout-ms "$(SIM_UI_SYNC_RELAY_DURATION_MS)" --max-stream-lag-ms "$(MAX_UI_LAG_MS)" --wait-timeout-ms "$(SIM_UI_SYNC_READY_TIMEOUT_MS)" > "$$fixture_log" 2>&1 & fixture_pid="$$!"; deadline=$$(( $$(date +%s) + ( $(SIM_UI_SYNC_READY_TIMEOUT_MS) / 1000 ) )); while [ ! -f "$$fixture_ready" ]; do if ! kill -0 "$$fixture_pid" 2>/dev/null; then blocked_reason="controlled simulator fixture exited before ready; see $$fixture_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$fixture_log" >&2; cleanup 1; fi; if [ "$$(date +%s)" -gt "$$deadline" ]; then blocked_reason="controlled simulator fixture did not become ready; see $$fixture_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$fixture_log" >&2; cleanup 1; fi; sleep 0.2; done; relay_hosts="$$(rtk node -e '\''const fs = require("fs"); const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(data.hosts);'\'' "$$fixture_ready")"; rtk node -e '\''const fs = require("fs"); const args = process.argv.slice(1); const ready = JSON.parse(fs.readFileSync(args[6], "utf8")); const iso = new Date(Date.now() + 600000).toISOString(); const expiresAt = iso.slice(0, iso.indexOf(".")) + "Z"; const config = Object.assign({ outputPath: args[1], hosts: ready.hosts, durationMS: Number(args[2]), sampleMS: Number(args[3]), readyPath: args[4], checkpointSweep: args[5] === "1", expiresAt }, ready.uiConfig || {}); fs.writeFileSync(args[0], JSON.stringify(config) + "\n");'\'' "$$config" "$$ui_samples" "$(SIM_UI_SYNC_DURATION_MS)" "$(SIM_UI_SYNC_SAMPLE_MS)" "$$ready_file" "$(SIM_UI_SYNC_CHECKPOINT_SWEEP)" "$$fixture_ready"; rtk node scripts/sim-ui-sync-config.mjs annotate --path "$$config" --simulator-udid "$$udid" --app-bundle-id "$(APP_BUNDLE_ID)" --app-data-container "$$app_data"; echo "running controlled displayed UI sampler on $(SIM) with hosts=$$relay_hosts"; if ! SIMULATOR_HOST_HOME="$$HOME" CODEX_DOCK_UI_TEST_SIMULATOR_UDID="$$udid" CODEX_DOCK_UI_TEST_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER="$$app_data" xcodebuild -quiet test-without-building -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" -only-testing:CodexDockUITests/CodexDockDisplayedSyncProofTests/testSamplesRelayBackedDockDisplayOverTime > "$$test_log" 2>&1; then blocked_reason="controlled sim UI test failed; see $$test_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$test_log" >&2; cleanup 1; fi; touch "$$fixture_stop"; if ! wait "$$fixture_pid"; then blocked_reason="controlled simulator fixture failed; see $$fixture_log"; echo "$$blocked_reason" >&2; tail -n 120 "$$fixture_log" >&2; write_blocked_proof "$$blocked_reason"; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; exit 1; fi; fixture_pid=""; rm -f "$$config"; rmdir "$$config_lock" 2>/dev/null || true; trap - INT TERM; rtk node scripts/dock-relay-simulator-ui-sync-proof.mjs --relay-report "$$relay_json" --ui-samples "$$ui_samples" --max-ui-lag-ms "$(MAX_UI_LAG_MS)" --json-out "$$report_json" --summary-out "$$report_md" --fail-on-diff; echo "wrote $$relay_json"; echo "wrote $$relay_md"; echo "wrote $$report_json"; echo "wrote $$report_md"'

sim-ui-controlled-matrix-verify:
	@rtk sh -c 'set -eu; if [ -z "$(SIM_UI_MATRIX_REPORT_DIRS)" ]; then echo "SIM_UI_MATRIX_REPORT_DIRS=<space-separated report dirs> is required" >&2; exit 2; fi; set --; for report_dir in $(SIM_UI_MATRIX_REPORT_DIRS); do set -- "$$@" --report-dir "$$report_dir"; done; rtk node scripts/dock-relay-controlled-simulator-matrix.mjs "$$@" --json-out "$(SIM_UI_MATRIX_JSON)" --summary-out "$(SIM_UI_MATRIX_MD)" --min-passes "$(SIM_UI_MATRIX_MIN_PASSES)" --max-ui-lag-ms "$(MAX_UI_LAG_MS)" --fail-on-diff; echo "wrote $(SIM_UI_MATRIX_JSON)"; echo "wrote $(SIM_UI_MATRIX_MD)"'

sim-ui-controlled-matrix-proof:
	@rtk sh -c 'set -eu; root="$(SIM_UI_CONTROLLED_MATRIX_ROOT)"; scenarios="$(SIM_UI_CONTROLLED_MATRIX_SCENARIOS)"; passes="$(SIM_UI_CONTROLLED_MATRIX_PASSES)"; if [ "$$passes" -lt 1 ]; then echo "SIM_UI_CONTROLLED_MATRIX_PASSES must be at least 1" >&2; exit 2; fi; python3 scripts/sim.py boot "$(SIM)"; matrix_udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; mkdir -p "$$root"; report_dirs=""; pass=1; while [ "$$pass" -le "$$passes" ]; do for scenario in $$scenarios; do duration="$(SIM_UI_SYNC_DURATION_MS)"; hold="$(SIM_UI_SYNC_SCENARIO_HOLD_MS)"; case "$$scenario" in archive-toggle|mutation-ack-projection-refresh-failure) duration="10000"; hold="3500";; detail-reconnect|foreground-resume-all-surfaces) duration="18000";; detail-history-request|detail-replay-pressure) duration="20000";; large-list-checkpoint|root-catchup-window-contract) duration="14000";; thread-activity|current-work-visible|server-rename-notification|server-status-notification|spawned-private-child-status-rollup) duration="7000"; hold="1500";; server-request) duration="12000";; rapid-mutations) duration="28000"; hold="2500";; multi-host-isolation) duration="16000";; source-refresh|live-lease-expiry|spawn-edge|resync-gap) duration="14000";; *) echo "unknown controlled simulator matrix scenario $$scenario" >&2; exit 2;; esac; scenario_dir="$$root/pass-$$pass/$$scenario"; echo "running controlled simulator matrix pass $$pass scenario $$scenario -> $$scenario_dir"; rtk make --no-print-directory sim-ui-controlled-scenario-sync-proof SIM="$$matrix_udid" SIM_UI_SYNC_SCENARIO="$$scenario" SIM_UI_SYNC_DIR="$$scenario_dir" SIM_UI_SYNC_DURATION_MS="$$duration" SIM_UI_SYNC_SAMPLE_MS="$(SIM_UI_CONTROLLED_MATRIX_SAMPLE_MS)" SIM_UI_SYNC_SCENARIO_HOLD_MS="$$hold" MAX_UI_LAG_MS="$(MAX_UI_LAG_MS)" SIM_UI_SYNC_CHECKPOINT_SWEEP="$(SIM_UI_SYNC_CHECKPOINT_SWEEP)" SIM_UI_SYNC_READY_TIMEOUT_MS="$(SIM_UI_SYNC_READY_TIMEOUT_MS)" SIM_UI_SYNC_RELAY_DURATION_MS="$(SIM_UI_SYNC_RELAY_DURATION_MS)" APP_DERIVED_DATA="$$scenario_dir/DerivedData"; report_dirs="$$report_dirs $$scenario_dir"; done; pass=$$((pass + 1)); done; matrix_json="$$root/controlled-simulator-matrix.json"; matrix_md="$$root/controlled-simulator-matrix.md"; rtk make --no-print-directory sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS="$$report_dirs" SIM_UI_MATRIX_JSON="$$matrix_json" SIM_UI_MATRIX_MD="$$matrix_md" SIM_UI_MATRIX_MIN_PASSES="$$passes" MAX_UI_LAG_MS="$(MAX_UI_LAG_MS)"; echo "wrote $$matrix_json"; echo "wrote $$matrix_md"'

sim-sync-audit: sim-ui-sync-proof

sim-config-verify: services
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; rtk node -- scripts/device-relay-config.mjs verify-env --input "$(HOST_ENV_FILE)" --hosts "$(CODEX_DOCK_HOSTS)"; echo "verified simulator $$udid config hosts=$(CODEX_DOCK_HOSTS)"'

device-install: services
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; if [ -z "$(DEVELOPMENT_TEAM)" ]; then echo "DEVELOPMENT_TEAM=<team-id> is required"; exit 2; fi; relay_hosts="$(DEVICE_RELAY_HOSTS)"; if [ -z "$$relay_hosts" ]; then if [ -n "$(DEVICE_RELAY_HOST)" ]; then relay_hosts="$(DEVICE_RELAY_HOST):$(DEVICE_RELAY_PORT)"; else case "$$device" in "$(IPHONE_17_PRO_DEVICE)") relay_hosts="$(IPHONE_17_PRO_RELAY_HOSTS)" ;; "$(IPHONE_14_DEVICE)") relay_hosts="$(IPHONE_14_RELAY_HOSTS)" ;; *) echo "DEVICE_RELAY_HOSTS=<host:port[,host:port...]> or DEVICE_RELAY_HOST=<host> is required for unknown device $$device" >&2; exit 2 ;; esac; fi; fi; log_dir="$(APP_BUILD_LOG_DIR)"; build_log="$$log_dir/app-device-build-$(APP_BUILD_NUMBER)-$$device.log"; install_log="$$log_dir/app-device-install-$(APP_BUILD_NUMBER)-$$device.log"; mkdir -p "$$log_dir"; action="build"; if [ "$(APP_FRESH_BUILD)" = "1" ]; then action="clean build"; fi; echo "building $(APP_SCHEME) for device $$device build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet -allowProvisioningUpdates -allowProvisioningDeviceRegistration -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$device" -derivedDataPath "$(APP_DERIVED_DATA)" $$action DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then echo "device build failed; see $$build_log" >&2; tail -n 80 "$$build_log" >&2; exit 1; fi; echo "installing device build $(APP_BUILD_NUMBER) on $$device"; if ! xcrun devicectl device install app --device "$$device" "$(DEVICE_APP_PATH)" > "$$install_log" 2>&1; then echo "device install failed; see $$install_log" >&2; tail -n 80 "$$install_log" >&2; exit 1; fi; line="$$(xcrun devicectl device info apps --device "$$device" | awk '\''/com\.aelaguiz\.CodexDockApp/ { print; found=1 } END { if (!found) exit 1 }'\'')"; installed_build="$$(printf "%s\n" "$$line" | awk '\''{ print $$NF }'\'')"; if [ "$$installed_build" != "$(APP_BUILD_NUMBER)" ]; then echo "installed device build $$installed_build did not match expected $(APP_BUILD_NUMBER)" >&2; exit 1; fi; rtk make --no-print-directory device-config DEVICE="$$device" DEVICE_RELAY_HOSTS="$$relay_hosts" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"; rtk make --no-print-directory device-launch DEVICE="$$device" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"; echo "installed $(APP_BUNDLE_ID) on $$device build $(APP_BUILD_NUMBER) using hosts=$$relay_hosts"'

device-install-iphone-17-pro:
	@rtk make --no-print-directory device-install DEVICE="$(IPHONE_17_PRO_DEVICE)" DEVICE_RELAY_HOSTS="$(IPHONE_17_PRO_RELAY_HOSTS)" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"

device-install-iphone-14:
	@rtk make --no-print-directory device-install DEVICE="$(IPHONE_14_DEVICE)" DEVICE_RELAY_HOSTS="$(IPHONE_14_RELAY_HOSTS)" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"

iphone-17-pro: device-install-iphone-17-pro

iphone-14: device-install-iphone-14

device-install-all:
	@rtk make --no-print-directory device-install-iphone-17-pro APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"
	@rtk make --no-print-directory device-install-iphone-14 APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"

device-config:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; relay_hosts="$(DEVICE_RELAY_HOSTS)"; if [ -z "$$relay_hosts" ]; then if [ -n "$(DEVICE_RELAY_HOST)" ]; then relay_hosts="$(DEVICE_RELAY_HOST):$(DEVICE_RELAY_PORT)"; else case "$$device" in "$(IPHONE_17_PRO_DEVICE)") relay_hosts="$(IPHONE_17_PRO_RELAY_HOSTS)" ;; "$(IPHONE_14_DEVICE)") relay_hosts="$(IPHONE_14_RELAY_HOSTS)" ;; *) echo "DEVICE_RELAY_HOSTS=<host:port[,host:port...]> or DEVICE_RELAY_HOST=<host> is required for unknown device $$device" >&2; exit 2 ;; esac; fi; fi; log_dir="$(APP_BUILD_LOG_DIR)"; scratch="/tmp/codex-client/device-config-$(APP_BUILD_NUMBER)-$$device"; payload_root="$$scratch/root"; payload="$$payload_root/CodexDock"; source_config="$$payload/relay-config.json"; copy_log="$$log_dir/device-config-$(APP_BUILD_NUMBER)-$$device.log"; mkdir -p "$$payload" "$$log_dir"; rtk node -- scripts/device-relay-config.mjs write --output "$$source_config" --hosts "$$relay_hosts"; echo "configuring $$device with hosts=$$relay_hosts"; if ! xcrun devicectl device copy to --device "$$device" --domain-type appDataContainer --domain-identifier "$(APP_BUNDLE_ID)" --source "$$payload_root" --destination "Library/Application Support" > "$$copy_log" 2>&1; then echo "device config copy failed; see $$copy_log" >&2; tail -n 80 "$$copy_log" >&2; exit 1; fi; rtk make --no-print-directory device-config-verify DEVICE="$$device" DEVICE_RELAY_HOSTS="$$relay_hosts" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"'

device-config-verify:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; relay_hosts="$(DEVICE_RELAY_HOSTS)"; if [ -z "$$relay_hosts" ]; then if [ -n "$(DEVICE_RELAY_HOST)" ]; then relay_hosts="$(DEVICE_RELAY_HOST):$(DEVICE_RELAY_PORT)"; else case "$$device" in "$(IPHONE_17_PRO_DEVICE)") relay_hosts="$(IPHONE_17_PRO_RELAY_HOSTS)" ;; "$(IPHONE_14_DEVICE)") relay_hosts="$(IPHONE_14_RELAY_HOSTS)" ;; *) echo "DEVICE_RELAY_HOSTS=<host:port[,host:port...]> or DEVICE_RELAY_HOST=<host> is required for unknown device $$device" >&2; exit 2 ;; esac; fi; fi; log_dir="$(APP_BUILD_LOG_DIR)"; scratch="/tmp/codex-client/device-config-verify-$(APP_BUILD_NUMBER)-$$device"; readback="$$scratch/relay-config.json"; copy_log="$$log_dir/device-config-verify-$(APP_BUILD_NUMBER)-$$device.log"; mkdir -p "$$scratch" "$$log_dir"; if ! xcrun devicectl device copy from --device "$$device" --domain-type appDataContainer --domain-identifier "$(APP_BUNDLE_ID)" --source "$(DEVICE_CONFIG_PATH)" --destination "$$readback" > "$$copy_log" 2>&1; then echo "device config readback failed; see $$copy_log" >&2; tail -n 80 "$$copy_log" >&2; exit 1; fi; rtk node -- scripts/device-relay-config.mjs verify --input "$$readback" --hosts "$$relay_hosts"; echo "verified $$device config hosts=$$relay_hosts"'

device-config-verify-all:
	@rtk make --no-print-directory device-config-verify DEVICE="$(IPHONE_17_PRO_DEVICE)" DEVICE_RELAY_HOSTS="$(IPHONE_17_PRO_RELAY_HOSTS)" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"
	@rtk make --no-print-directory device-config-verify DEVICE="$(IPHONE_14_DEVICE)" DEVICE_RELAY_HOSTS="$(IPHONE_14_RELAY_HOSTS)" APP_BUILD_NUMBER="$(APP_BUILD_NUMBER)"

device-launch:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; log_dir="$(APP_BUILD_LOG_DIR)"; launch_log="$$log_dir/device-launch-$(APP_BUILD_NUMBER)-$$device.log"; mkdir -p "$$log_dir"; if ! xcrun devicectl device process launch --device "$$device" --terminate-existing "$(APP_BUNDLE_ID)" > "$$launch_log" 2>&1; then echo "device launch failed; see $$launch_log" >&2; tail -n 80 "$$launch_log" >&2; exit 1; fi; echo "launched $(APP_BUNDLE_ID) on $$device"'

devices:
	@rtk python3 scripts/device.py list

run: app

sims:
	@rtk python3 scripts/sim.py list

sim:
	@rtk python3 scripts/sim.py open "$(SIM)"

sim-list: sims

sim-boot: sim
