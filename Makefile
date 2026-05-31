APP_SERVER_DIR ?= .codex-dock
APP_SERVER_HOST ?= $(shell tailscale status --json 2>/dev/null | python3 -c 'import json, sys; dns = json.load(sys.stdin).get("Self", {}).get("DNSName", "").rstrip("."); print(dns) if dns else sys.exit(1)' 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || hostname)
APP_SERVER_PORT ?= 4500
APP_SERVER_LISTEN ?= ws://127.0.0.1:$(APP_SERVER_PORT)
APP_SERVER_WS ?= ws://127.0.0.1:$(APP_SERVER_PORT)
APP_SERVER_LABEL ?= com.aelaguiz.codex-dock.app-server
CODEX_BIN ?= /Users/aelaguiz/.local/bin/codex
NODE_BIN ?= /opt/homebrew/bin/node
APP_SERVER_ABS_DIR := $(CURDIR)/$(APP_SERVER_DIR)
APP_SERVER_PID := $(APP_SERVER_ABS_DIR)/app-server.pid
APP_SERVER_TOKEN := $(APP_SERVER_ABS_DIR)/app-server.token
APP_SERVER_LOG := $(APP_SERVER_ABS_DIR)/logs/app-server.log
APP_SERVER_ERR_LOG := $(APP_SERVER_ABS_DIR)/logs/app-server.err.log
APP_SERVER_PLIST := $(APP_SERVER_ABS_DIR)/services/$(APP_SERVER_LABEL).plist
DOCK_RELAY_PORT ?= 4510
DOCK_RELAY_LISTEN_HOST ?= 0.0.0.0
DOCK_RELAY_HISTORY_WS ?= ws://127.0.0.1:$(APP_SERVER_PORT)
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
HOST_SERVICE_SCRIPT ?= scripts/codex-dock-host-service.mjs
HOST_SERVICE_PLATFORM ?= macos
HOST_SERVICE_NETWORK_PROFILE ?= lan
HOST_SERVICE_WAIT_ATTEMPTS ?= 10
HOST_SERVICE_STATUS_FILE := $(APP_SERVER_ABS_DIR)/host-service.status.json
SIM ?= iPhone 17
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
THREAD_FIDELITY_REPORT ?= /tmp/codex-client/relay-thread-fidelity-$(shell date -u +%Y%m%dT%H%M%SZ).json
RELAY_DEBUG_BUNDLE ?= /tmp/codex-client/relay-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ).json
RELAY_HOST_COMPARE_REPORT ?= /tmp/codex-client/relay-host-compare-$(shell date -u +%Y%m%dT%H%M%SZ).json
HOSTS ?= $(CODEX_DOCK_HOSTS)
SIM_DEBUG_BUNDLE_DIR ?= /tmp/codex-client/sim-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ)
DEVICE_DEBUG_BUNDLE_DIR ?= /tmp/codex-client/device-debug-bundle-$(shell date -u +%Y%m%dT%H%M%SZ)
APP_BUILD_LOG_DIR := $(APP_SERVER_ABS_DIR)/logs
HOST_SERVICE_ARGS = --platform "$(HOST_SERVICE_PLATFORM)" --runtime-dir "$(APP_SERVER_DIR)" --host-id "$(CODEX_DOCK_REAL_HOST_ID)" --host-name "$(CODEX_DOCK_REAL_HOST_NAME)" --network-profile "$(HOST_SERVICE_NETWORK_PROFILE)" --public-host "$(APP_SERVER_HOST)" --raw-app-server-listen "$(APP_SERVER_LISTEN)" --relay-history-url "$(DOCK_RELAY_HISTORY_WS)" --relay-public-url "$(DOCK_RELAY_WS)" --relay-listen-host "$(DOCK_RELAY_LISTEN_HOST)" --relay-port "$(DOCK_RELAY_PORT)" --phone-auth "none" --service-env-file "$(CURDIR)/$(ENV_FILE)" --host-env-file "$(CURDIR)/$(HOST_ENV_FILE)" --raw-token-file "$(APP_SERVER_TOKEN)" --codex-bin "$(CODEX_BIN)" --node-bin "$(NODE_BIN)" --app-server-label "$(APP_SERVER_LABEL)" --relay-label "$(DOCK_RELAY_LABEL)" --relay-script "$(CURDIR)/scripts/dock-relay.mjs"

.DEFAULT_GOAL := help

.PHONY: help contract-generate contract-check app app-test sim-config-verify device-install device-install-iphone-17-pro device-install-iphone-14 iphone-17-pro iphone-14 device-install-all device-config device-config-verify device-config-verify-all device-launch devices services env-file node-deps host-service-install host-service-start host-service-status host-service-wait host-service-stop host-service-restart host-service-logs host-service-doctor app-server app-server-status app-server-env app-server-stop app-server-restart dock-relay dock-relay-status dock-relay-stop dock-relay-restart relay-probe relay-thread-fidelity relay-leak-check relay-doctor relay-debug-bundle relay-host-compare sim-debug-bundle device-debug-bundle app-server-logs dock-relay-logs sim-logs device-logs sims sim sim-list sim-boot run

help:
	@printf "%s\n" "Codex Dock commands:"
	@printf "%s\n" "  rtk make contract-generate Regenerate generated contract DTOs"
	@printf "%s\n" "  rtk make contract-check    Check DockThreadCard contract fixtures and generated DTOs"
	@printf "%s\n" "  rtk make app SIM='iPhone 17' Reuse a running simulator app; otherwise build/install/launch"
	@printf "%s\n" "  FORCE_LAUNCH=1 rtk make app SIM=<UDID> Fresh build/install/relaunch by simulator ID"
	@printf "%s\n" "  rtk make app-test SIM='iPhone 17' Run generated-project app tests in a simulator"
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
	@printf "%s\n" "  rtk make app-server        Compatibility alias for the host service bundle"
	@printf "%s\n" "  rtk make dock-relay        Compatibility alias for the host service bundle"
	@printf "%s\n" "  rtk make app-server-status Check host service bundle status"
	@printf "%s\n" "  rtk make dock-relay-status Check host service bundle status"
	@printf "%s\n" "  rtk make relay-probe      Compare raw history and relay thread/list cursor/top row"
	@printf "%s\n" "  rtk make relay-thread-fidelity Cross-check relay sessions against Codex disk/SQLite"
	@printf "%s\n" "  rtk make relay-leak-check Repeat relay thread/list and verify upstream socket count is flat"
	@printf "%s\n" "  rtk make relay-doctor     Print relay-focused redacted diagnostics"
	@printf "%s\n" "  rtk make relay-debug-bundle Fetch the relay route-health debug bundle"
	@printf "%s\n" "  rtk make relay-host-compare HOSTS=host:port,host:port Compare route health across relays"
	@printf "%s\n" "  rtk make sim-debug-bundle SIM='iPhone 14' Copy app-owned diagnostics from simulator"
	@printf "%s\n" "  rtk make device-debug-bundle DEVICE=<UDID> Copy app-owned diagnostics from a physical iPhone"
	@printf "%s\n" "  rtk make app-server-env    Print env for raw dev smoke tests"
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
	@rtk sh -c 'set -eu; echo "export CODEX_DOCK_LOOPBACK_APP_SERVER_WS=$(DOCK_RELAY_HISTORY_WS)"; echo "export CODEX_DOCK_TEST_APP_SERVER_WS=$(DOCK_RELAY_WS)"; echo "export CODEX_DOCK_TEST_APP_SERVER_BEARER_TOKEN_FILE=$(APP_SERVER_TOKEN)"'

app-server-stop: host-service-stop

dock-relay-stop: host-service-stop

app-server-restart: host-service-restart

dock-relay-restart: host-service-restart

relay-probe:
	@CODEX_DOCK_RELAY_WS="$(DOCK_RELAY_PROBE_WS)" CODEX_DOCK_HISTORY_APP_SERVER_WS="$(DOCK_RELAY_HISTORY_WS)" CODEX_DOCK_HISTORY_TOKEN_FILE="$(APP_SERVER_TOKEN)" rtk node -- scripts/dock-relay-probe.mjs

relay-thread-fidelity:
	@CODEX_DOCK_RELAY_WS="$(DOCK_RELAY_PROBE_WS)" rtk node -- scripts/dock-relay-thread-fidelity.mjs --json-out "$(THREAD_FIDELITY_REPORT)" --summary-only

relay-leak-check:
	@CODEX_DOCK_RELAY_WS="$(DOCK_RELAY_PROBE_WS)" CODEX_DOCK_LEAK_CHECK_ITERATIONS="$(DOCK_RELAY_LEAK_CHECK_ITERATIONS)" rtk node -- scripts/dock-relay-leak-check.mjs

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
	@rtk tail -n 200 -f "$(APP_SERVER_LOG)" "$(APP_SERVER_ERR_LOG)"

dock-relay-logs:
	@rtk tail -n 200 -f "$(DOCK_RELAY_ERR_LOG)"

sim-logs:
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; xcrun simctl spawn "$$udid" log stream --style "$(LOG_STYLE)" --level debug --predicate '\''$(LOG_PREDICATE)'\'''

device-logs:
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; output="$(DEVICE_LOG_OUTPUT)"; mkdir -p "$$(dirname "$$output")"; xcrun log collect --device-udid "$$device" --last "$(LOG_LAST)" --predicate '\''$(LOG_PREDICATE)'\'' --output "$$output"; echo "wrote $$output"'

app: services
	@rtk sh -c 'set -eu; python3 scripts/sim.py boot "$(SIM)"; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; if [ "$(FORCE_LAUNCH)" != "1" ] && python3 scripts/sim.py app-running "$(SIM)" "$(APP_BUNDLE_ID)" >/dev/null; then echo "$(APP_BUNDLE_ID) is already running on simulator $$udid; skipped build/install/launch. Use FORCE_LAUNCH=1 to replace it."; exit 0; fi; python3 scripts/sim.py terminate-others "$(SIM)" "$(APP_BUNDLE_ID)"; rtk xcodegen generate --spec project.yml; host_env="$(HOST_ENV_FILE)"; log_dir="$(APP_BUILD_LOG_DIR)"; build_log="$$log_dir/app-sim-build-$(APP_BUILD_NUMBER).log"; install_log="$$log_dir/app-sim-install-$(APP_BUILD_NUMBER).log"; mkdir -p "$$log_dir"; if [ ! -f "$$host_env" ]; then echo "missing generated app host env $$host_env" >&2; exit 2; fi; action="build"; if [ "$(APP_FRESH_BUILD)" = "1" ]; then action="clean build"; fi; echo "building $(APP_SCHEME) for simulator $$udid build $(APP_BUILD_NUMBER)"; if ! xcodebuild -quiet -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" $$action CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$build_log" 2>&1; then echo "simulator build failed; see $$build_log" >&2; tail -n 80 "$$build_log" >&2; exit 1; fi; echo "installing simulator build $(APP_BUILD_NUMBER)"; if ! xcrun simctl install "$$udid" "$(APP_PATH)" > "$$install_log" 2>&1; then echo "simulator install failed; see $$install_log" >&2; tail -n 80 "$$install_log" >&2; exit 1; fi; installed_app="$$(xcrun simctl get_app_container "$$udid" "$(APP_BUNDLE_ID)" app)"; installed_build="$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$$installed_app/Info.plist")"; if [ "$$installed_build" != "$(APP_BUILD_NUMBER)" ]; then echo "installed simulator build $$installed_build did not match expected $(APP_BUILD_NUMBER)" >&2; exit 1; fi; launch_hosts=""; while IFS= read -r line || [ -n "$$line" ]; do case "$$line" in ""|\#*) continue;; esac; case "$$line" in *=*) key="$${line%%=*}"; value="$${line#*=}";; *) continue;; esac; case "$$key" in CODEX_DOCK_*) export "SIMCTL_CHILD_$$key=$$value";; *) continue;; esac; if [ "$$key" = CODEX_DOCK_HOSTS ]; then launch_hosts="$$value"; fi; done < "$$host_env"; echo "launch host env: $$host_env"; echo "launch hosts: $$launch_hosts"; xcrun simctl launch --terminate-running-process "$$udid" "$(APP_BUNDLE_ID)" > "$$install_log" 2>&1; echo "launched $(APP_BUNDLE_ID) on simulator $$udid build $(APP_BUILD_NUMBER)"'

app-test: services
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; log_dir="$(APP_BUILD_LOG_DIR)"; test_log="$$log_dir/app-test-$(APP_BUILD_NUMBER).log"; mkdir -p "$$log_dir"; echo "testing $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"; if ! CODEX_DOCK_UI_TEST_HOSTS="$(CODEX_DOCK_UI_TEST_HOSTS)" xcodebuild -quiet test -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" CURRENT_PROJECT_VERSION="$(APP_BUILD_NUMBER)" > "$$test_log" 2>&1; then echo "app test failed; see $$test_log" >&2; tail -n 80 "$$test_log" >&2; exit 1; fi; echo "tested $(APP_SCHEME) on simulator $$udid build $(APP_BUILD_NUMBER)"'

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
