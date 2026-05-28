APP_SERVER_DIR ?= .codex-dock
APP_SERVER_HOST ?= 192.168.50.117
APP_SERVER_PORT ?= 4500
APP_SERVER_LISTEN ?= ws://0.0.0.0:$(APP_SERVER_PORT)
APP_SERVER_WS ?= ws://$(APP_SERVER_HOST):$(APP_SERVER_PORT)
APP_SERVER_LABEL ?= com.aelaguiz.codex-dock.app-server
CODEX_BIN ?= /Users/aelaguiz/.local/bin/codex
NODE_BIN ?= /opt/homebrew/bin/node
APP_SERVER_ABS_DIR := $(CURDIR)/$(APP_SERVER_DIR)
APP_SERVER_PID := $(APP_SERVER_ABS_DIR)/app-server.pid
APP_SERVER_TOKEN := $(APP_SERVER_ABS_DIR)/app-server.token
APP_SERVER_LOG := $(APP_SERVER_ABS_DIR)/app-server.log
APP_SERVER_ERR_LOG := $(APP_SERVER_ABS_DIR)/app-server.err.log
APP_SERVER_PLIST := $(APP_SERVER_ABS_DIR)/$(APP_SERVER_LABEL).plist
DOCK_RELAY_PORT ?= 4510
DOCK_RELAY_LISTEN_HOST ?= 0.0.0.0
DOCK_RELAY_HISTORY_WS ?= ws://127.0.0.1:$(APP_SERVER_PORT)
DOCK_RELAY_WS ?= ws://$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)
DOCK_RELAY_LABEL ?= com.aelaguiz.codex-dock.relay
DOCK_RELAY_PID := $(APP_SERVER_ABS_DIR)/dock-relay.pid
DOCK_RELAY_LOG := $(APP_SERVER_ABS_DIR)/dock-relay.log
DOCK_RELAY_ERR_LOG := $(APP_SERVER_ABS_DIR)/dock-relay.err.log
DOCK_RELAY_PLIST := $(APP_SERVER_ABS_DIR)/$(DOCK_RELAY_LABEL).plist
ENV_FILE ?= .env
SIM ?= iPhone 17
APP_SCHEME ?= CodexDockApp
APP_BUNDLE_ID ?= com.aelaguiz.CodexDockApp
APP_DERIVED_DATA ?= $(APP_SERVER_ABS_DIR)/DerivedData
APP_PATH := $(APP_DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_SCHEME).app
DEVICE ?=
DEVICE_NAME ?= iPhone 14
DEVELOPMENT_TEAM ?= R6B8KXF3QW
DEVICE_APP_PATH := $(APP_DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_SCHEME).app
CODEX_DOCK_HOSTS ?= Amir-M5
CODEX_DOCK_HOST_AMIR_M5_NAME ?= Amir-M5
CODEX_DOCK_HOST_AMIR_M5_WS ?= $(DOCK_RELAY_WS)
CODEX_DOCK_HOST_HOME_NAME ?= Home
CODEX_DOCK_HOST_HOME_WS ?=
CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL ?= gpt-4o-transcribe

.DEFAULT_GOAL := help

.PHONY: help app device-install devices services env-file node-deps app-server app-server-status app-server-env app-server-stop app-server-restart dock-relay dock-relay-status dock-relay-stop dock-relay-restart sims sim sim-list sim-boot run

help:
	@printf "%s\n" "Codex Dock commands:"
	@printf "%s\n" "  rtk make app SIM='iPhone 17' Build/install/launch the app in a simulator"
	@printf "%s\n" "  rtk make app SIM=<UDID>    Build/install/launch the app by simulator ID"
	@printf "%s\n" "  rtk make device-install    Build/install on the default physical iPhone"
	@printf "%s\n" "  rtk make device-install DEVICE=<UDID> Build/install on a specific physical iPhone"
	@printf "%s\n" "  rtk make devices           List physical iPhones known to CoreDevice"
	@printf "%s\n" "  rtk make services          Start/reuse every local service the app needs"
	@printf "%s\n" "  rtk make app-server        Start/reuse the raw persistent LAN app-server"
	@printf "%s\n" "  rtk make dock-relay        Start/reuse the phone-reachable live-session relay"
	@printf "%s\n" "  rtk make app-server-status Check raw app-server PID and readyz"
	@printf "%s\n" "  rtk make dock-relay-status Check relay PID and readyz"
	@printf "%s\n" "  rtk make app-server-env    Print env for raw dev smoke tests"
	@printf "%s\n" "  rtk make sims              List available simulators"
	@printf "%s\n" "  rtk make sim SIM='iPhone 17' Boot/open a simulator by name"
	@printf "%s\n" "  rtk make sim SIM=<UDID>    Boot/open a simulator by ID"

services: env-file app-server dock-relay

env-file:
	@rtk sh -c 'set -eu; openai_key="$${OPENAI_API_KEY:-}"; if [ -z "$$openai_key" ] && [ -f "$(ENV_FILE)" ]; then openai_key="$$(awk -F= '\''$$1=="OPENAI_API_KEY"{sub(/^[^=]*=/,""); print; exit}'\'' "$(ENV_FILE)")"; fi; { echo "CODEX_DOCK_HOSTS=$(CODEX_DOCK_HOSTS)"; echo "CODEX_DOCK_HOST_AMIR_M5_WS=$(CODEX_DOCK_HOST_AMIR_M5_WS)"; echo "CODEX_DOCK_HOST_AMIR_M5_NAME=$(CODEX_DOCK_HOST_AMIR_M5_NAME)"; echo "CODEX_DOCK_HOST_HOME_WS=$(CODEX_DOCK_HOST_HOME_WS)"; echo "CODEX_DOCK_HOST_HOME_NAME=$(CODEX_DOCK_HOST_HOME_NAME)"; echo "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=$(DOCK_RELAY_WS)"; echo "CODEX_DOCK_REAL_HOST_ID=Amir-M5"; echo "CODEX_DOCK_REAL_HOST_NAME=Amir-M5"; echo "CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL=$(CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL)"; if [ -n "$$openai_key" ]; then echo "OPENAI_API_KEY=$$openai_key"; fi; } > "$(ENV_FILE)"; echo "wrote $(ENV_FILE)"'

node-deps:
	@rtk sh -c 'set -eu; if [ ! -d node_modules/ws ]; then npm ci; else echo "node dependencies already installed"; fi'

app-server:
	@rtk mkdir -p "$(APP_SERVER_ABS_DIR)"
	@rtk sh -c 'set -eu; token="$(APP_SERVER_TOKEN)"; if [ ! -s "$$token" ]; then umask 077; openssl rand -base64 32 > "$$token"; fi'
	@rtk sh -c 'set -eu; { printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"; printf "%s\n" "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"; printf "%s\n" "<plist version=\"1.0\">"; printf "%s\n" "<dict>"; printf "%s\n" "  <key>Label</key>"; printf "%s\n" "  <string>$(APP_SERVER_LABEL)</string>"; printf "%s\n" "  <key>ProgramArguments</key>"; printf "%s\n" "  <array>"; printf "%s\n" "    <string>$(CODEX_BIN)</string>"; printf "%s\n" "    <string>app-server</string>"; printf "%s\n" "    <string>--listen</string>"; printf "%s\n" "    <string>$(APP_SERVER_LISTEN)</string>"; printf "%s\n" "    <string>--ws-auth</string>"; printf "%s\n" "    <string>capability-token</string>"; printf "%s\n" "    <string>--ws-token-file</string>"; printf "%s\n" "    <string>$(APP_SERVER_TOKEN)</string>"; printf "%s\n" "  </array>"; printf "%s\n" "  <key>WorkingDirectory</key>"; printf "%s\n" "  <string>$(CURDIR)</string>"; printf "%s\n" "  <key>EnvironmentVariables</key>"; printf "%s\n" "  <dict>"; printf "%s\n" "    <key>HOME</key>"; printf "%s\n" "    <string>$(HOME)</string>"; printf "%s\n" "    <key>PATH</key>"; printf "%s\n" "    <string>$(HOME)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>"; printf "%s\n" "  </dict>"; printf "%s\n" "  <key>RunAtLoad</key>"; printf "%s\n" "  <true/>"; printf "%s\n" "  <key>KeepAlive</key>"; printf "%s\n" "  <true/>"; printf "%s\n" "  <key>StandardOutPath</key>"; printf "%s\n" "  <string>$(APP_SERVER_LOG)</string>"; printf "%s\n" "  <key>StandardErrorPath</key>"; printf "%s\n" "  <string>$(APP_SERVER_ERR_LOG)</string>"; printf "%s\n" "</dict>"; printf "%s\n" "</plist>"; } > "$(APP_SERVER_PLIST)"'
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(APP_SERVER_LABEL)"; if launchctl print "$$service" >/dev/null 2>&1; then echo "codex app-server launch agent already loaded"; else launchctl bootstrap "gui/$$(id -u)" "$(APP_SERVER_PLIST)"; echo "loaded launch agent $(APP_SERVER_LABEL)"; fi; echo "endpoint: $(APP_SERVER_WS)"; echo "token file: $(APP_SERVER_TOKEN)"; echo "log: $(APP_SERVER_LOG)"'
	@rtk sh -c 'set -eu; for _ in 1 2 3 4 5; do if curl -fsS "http://$(APP_SERVER_HOST):$(APP_SERVER_PORT)/readyz" >/dev/null 2>&1; then echo "ready: http://$(APP_SERVER_HOST):$(APP_SERVER_PORT)/readyz"; exit 0; fi; sleep 1; done; echo "app-server did not become ready; log follows:"; tail -n 40 "$(APP_SERVER_LOG)"; exit 1'
	@rtk make app-server-status

app-server-status:
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(APP_SERVER_LABEL)"; if ! launchctl print "$$service" >/dev/null 2>&1; then echo "codex app-server launch agent is not loaded"; exit 1; fi; pid="$$(launchctl print "$$service" | sed -n "s/^[[:space:]]*pid = //p" | head -n 1 || true)"; if [ -n "$$pid" ]; then echo "$$pid" > "$(APP_SERVER_PID)"; echo "codex app-server running pid $$pid"; else rm -f "$(APP_SERVER_PID)"; echo "codex app-server launch agent is loaded; pid unavailable"; fi; echo "endpoint: $(APP_SERVER_WS)"; echo "token file: $(APP_SERVER_TOKEN)"; echo "log: $(APP_SERVER_LOG)"'
	@rtk curl -i --max-time 5 "http://$(APP_SERVER_HOST):$(APP_SERVER_PORT)/readyz"

app-server-env:
	@rtk sh -c 'set -eu; echo "export CODEX_DOCK_LOOPBACK_APP_SERVER_WS=$(DOCK_RELAY_HISTORY_WS)"; echo "export CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=$(DOCK_RELAY_WS)"; echo "export CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=$(APP_SERVER_TOKEN)"; echo "export CODEX_DOCK_REAL_HOST_ID=Amir-M5"; echo "export CODEX_DOCK_REAL_HOST_NAME=Amir-M5"'

app-server-stop:
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(APP_SERVER_LABEL)"; if launchctl bootout "gui/$$(id -u)" "$(APP_SERVER_PLIST)" >/dev/null 2>&1 || launchctl bootout "$$service" >/dev/null 2>&1; then echo "stopped launch agent $(APP_SERVER_LABEL)"; else echo "codex app-server launch agent was not loaded"; fi; rm -f "$(APP_SERVER_PID)"'

app-server-restart: app-server-stop app-server

dock-relay: node-deps env-file app-server
	@rtk mkdir -p "$(APP_SERVER_ABS_DIR)"
	@rtk sh -c 'set -eu; { printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"; printf "%s\n" "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"; printf "%s\n" "<plist version=\"1.0\">"; printf "%s\n" "<dict>"; printf "%s\n" "  <key>Label</key>"; printf "%s\n" "  <string>$(DOCK_RELAY_LABEL)</string>"; printf "%s\n" "  <key>ProgramArguments</key>"; printf "%s\n" "  <array>"; printf "%s\n" "    <string>$(NODE_BIN)</string>"; printf "%s\n" "    <string>$(CURDIR)/scripts/dock-relay.mjs</string>"; printf "%s\n" "    <string>--listen-host</string>"; printf "%s\n" "    <string>$(DOCK_RELAY_LISTEN_HOST)</string>"; printf "%s\n" "    <string>--port</string>"; printf "%s\n" "    <string>$(DOCK_RELAY_PORT)</string>"; printf "%s\n" "    <string>--phone-auth</string>"; printf "%s\n" "    <string>none</string>"; printf "%s\n" "    <string>--env-file</string>"; printf "%s\n" "    <string>$(CURDIR)/$(ENV_FILE)</string>"; printf "%s\n" "    <string>--bonjour-name</string>"; printf "%s\n" "    <string>$(CODEX_DOCK_HOST_AMIR_M5_NAME)</string>"; printf "%s\n" "    <string>--history-url</string>"; printf "%s\n" "    <string>$(DOCK_RELAY_HISTORY_WS)</string>"; printf "%s\n" "    <string>--history-auth-token-file</string>"; printf "%s\n" "    <string>$(APP_SERVER_TOKEN)</string>"; printf "%s\n" "    <string>--openai-transcription-model</string>"; printf "%s\n" "    <string>$(CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL)</string>"; printf "%s\n" "  </array>"; printf "%s\n" "  <key>WorkingDirectory</key>"; printf "%s\n" "  <string>$(CURDIR)</string>"; printf "%s\n" "  <key>EnvironmentVariables</key>"; printf "%s\n" "  <dict>"; printf "%s\n" "    <key>HOME</key>"; printf "%s\n" "    <string>$(HOME)</string>"; printf "%s\n" "    <key>PATH</key>"; printf "%s\n" "    <string>$(HOME)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>"; printf "%s\n" "  </dict>"; printf "%s\n" "  <key>RunAtLoad</key>"; printf "%s\n" "  <true/>"; printf "%s\n" "  <key>KeepAlive</key>"; printf "%s\n" "  <true/>"; printf "%s\n" "  <key>StandardOutPath</key>"; printf "%s\n" "  <string>$(DOCK_RELAY_LOG)</string>"; printf "%s\n" "  <key>StandardErrorPath</key>"; printf "%s\n" "  <string>$(DOCK_RELAY_ERR_LOG)</string>"; printf "%s\n" "</dict>"; printf "%s\n" "</plist>"; } > "$(DOCK_RELAY_PLIST)"'
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(DOCK_RELAY_LABEL)"; if launchctl print "$$service" >/dev/null 2>&1; then launchctl bootout "$$service" >/dev/null 2>&1 || launchctl bootout "gui/$$(id -u)" "$(DOCK_RELAY_PLIST)" >/dev/null 2>&1 || true; sleep 1; fi; if ! launchctl bootstrap "gui/$$(id -u)" "$(DOCK_RELAY_PLIST)"; then sleep 1; launchctl bootout "$$service" >/dev/null 2>&1 || launchctl bootout "gui/$$(id -u)" "$(DOCK_RELAY_PLIST)" >/dev/null 2>&1 || true; sleep 1; launchctl bootstrap "gui/$$(id -u)" "$(DOCK_RELAY_PLIST)"; fi; echo "loaded launch agent $(DOCK_RELAY_LABEL)"; echo "endpoint: $(DOCK_RELAY_WS)"; echo "history endpoint: $(DOCK_RELAY_HISTORY_WS)"; echo "phone auth: none"; echo "bonjour: _codexdock._tcp"; echo "log: $(DOCK_RELAY_LOG)"'
	@rtk sh -c 'set -eu; for _ in 1 2 3 4 5; do if curl -fsS "http://$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)/readyz" >/dev/null 2>&1; then echo "ready: http://$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)/readyz"; exit 0; fi; sleep 1; done; echo "dock relay did not become ready; log follows:"; tail -n 80 "$(DOCK_RELAY_ERR_LOG)" 2>/dev/null || true; exit 1'
	@rtk make dock-relay-status

dock-relay-status:
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(DOCK_RELAY_LABEL)"; if ! launchctl print "$$service" >/dev/null 2>&1; then echo "codex dock relay launch agent is not loaded"; exit 1; fi; pid="$$(launchctl print "$$service" | sed -n "s/^[[:space:]]*pid = //p" | head -n 1 || true)"; if [ -n "$$pid" ]; then echo "$$pid" > "$(DOCK_RELAY_PID)"; echo "codex dock relay running pid $$pid"; else rm -f "$(DOCK_RELAY_PID)"; echo "codex dock relay launch agent is loaded; pid unavailable"; fi; echo "endpoint: $(DOCK_RELAY_WS)"; echo "history endpoint: $(DOCK_RELAY_HISTORY_WS)"; echo "phone auth: none"; echo "log: $(DOCK_RELAY_LOG)"; echo "err log: $(DOCK_RELAY_ERR_LOG)"'
	@rtk curl -i --max-time 5 "http://$(APP_SERVER_HOST):$(DOCK_RELAY_PORT)/readyz"

dock-relay-stop:
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(DOCK_RELAY_LABEL)"; if launchctl bootout "gui/$$(id -u)" "$(DOCK_RELAY_PLIST)" >/dev/null 2>&1 || launchctl bootout "$$service" >/dev/null 2>&1; then echo "stopped launch agent $(DOCK_RELAY_LABEL)"; else echo "codex dock relay launch agent was not loaded"; fi; rm -f "$(DOCK_RELAY_PID)"'

dock-relay-restart: dock-relay-stop dock-relay

app: services
	@rtk python3 scripts/sim.py boot "$(SIM)"
	@rtk python3 scripts/sim.py terminate-others "$(SIM)" "$(APP_BUNDLE_ID)"
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; udid="$$(python3 scripts/sim.py resolve "$(SIM)")"; echo "building $(APP_SCHEME) for $$udid"; xcodebuild -quiet -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$udid" -derivedDataPath "$(APP_DERIVED_DATA)" build; echo "installing $(APP_PATH)"; xcrun simctl install "$$udid" "$(APP_PATH)"; echo "launch endpoint: $(DOCK_RELAY_WS)"; echo "launch hosts: $(CODEX_DOCK_HOSTS)"; SIMCTL_CHILD_CODEX_DOCK_HOSTS="$(CODEX_DOCK_HOSTS)" SIMCTL_CHILD_CODEX_DOCK_HOST_AMIR_M5_WS="$(CODEX_DOCK_HOST_AMIR_M5_WS)" SIMCTL_CHILD_CODEX_DOCK_HOST_AMIR_M5_NAME="$(CODEX_DOCK_HOST_AMIR_M5_NAME)" SIMCTL_CHILD_CODEX_DOCK_HOST_HOME_WS="$(CODEX_DOCK_HOST_HOME_WS)" SIMCTL_CHILD_CODEX_DOCK_HOST_HOME_NAME="$(CODEX_DOCK_HOST_HOME_NAME)" SIMCTL_CHILD_CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS="$(DOCK_RELAY_WS)" SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_ID=Amir-M5 SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_NAME=Amir-M5 xcrun simctl launch --terminate-running-process "$$udid" "$(APP_BUNDLE_ID)"; echo "launched $(APP_BUNDLE_ID) on $$udid"'

device-install: services
	@rtk xcodegen generate --spec project.yml
	@rtk sh -c 'set -eu; device="$(DEVICE)"; if [ -z "$$device" ]; then device="$$(python3 scripts/device.py resolve "$(DEVICE_NAME)")"; fi; if [ -z "$(DEVELOPMENT_TEAM)" ]; then echo "DEVELOPMENT_TEAM=<team-id> is required"; exit 2; fi; echo "building $(APP_SCHEME) for $$device with team $(DEVELOPMENT_TEAM)"; xcodebuild -quiet -allowProvisioningUpdates -allowProvisioningDeviceRegistration -project CodexDock.xcodeproj -scheme "$(APP_SCHEME)" -destination "id=$$device" -derivedDataPath "$(APP_DERIVED_DATA)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Automatic build; echo "installing $(DEVICE_APP_PATH) on $$device"; xcrun devicectl device install app --device "$$device" "$(DEVICE_APP_PATH)"; echo "installed $(APP_BUNDLE_ID) on $$device"'

devices:
	@rtk python3 scripts/device.py list

run: app

sims:
	@rtk python3 scripts/sim.py list

sim:
	@rtk python3 scripts/sim.py boot "$(SIM)"

sim-list: sims

sim-boot: sim
