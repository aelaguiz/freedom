APP_SERVER_DIR ?= .codex-dock
APP_SERVER_HOST ?= 192.168.50.117
APP_SERVER_PORT ?= 4500
APP_SERVER_LISTEN ?= ws://0.0.0.0:$(APP_SERVER_PORT)
APP_SERVER_WS ?= ws://$(APP_SERVER_HOST):$(APP_SERVER_PORT)
APP_SERVER_LABEL ?= com.aelaguiz.codex-dock.app-server
CODEX_BIN ?= /Users/aelaguiz/.local/bin/codex
APP_SERVER_ABS_DIR := $(CURDIR)/$(APP_SERVER_DIR)
APP_SERVER_PID := $(APP_SERVER_ABS_DIR)/app-server.pid
APP_SERVER_TOKEN := $(APP_SERVER_ABS_DIR)/app-server.token
APP_SERVER_LOG := $(APP_SERVER_ABS_DIR)/app-server.log
APP_SERVER_ERR_LOG := $(APP_SERVER_ABS_DIR)/app-server.err.log
APP_SERVER_PLIST := $(APP_SERVER_ABS_DIR)/$(APP_SERVER_LABEL).plist

.PHONY: app-server app-server-status app-server-env app-server-stop app-server-restart

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
	@rtk sh -c 'set -eu; echo "export CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=$(APP_SERVER_WS)"; echo "export CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=$(APP_SERVER_TOKEN)"; echo "export CODEX_DOCK_REAL_HOST_ID=Amir-M5"; echo "export CODEX_DOCK_REAL_HOST_NAME=Amir-M5"'

app-server-stop:
	@rtk sh -c 'set -eu; service="gui/$$(id -u)/$(APP_SERVER_LABEL)"; if launchctl bootout "gui/$$(id -u)" "$(APP_SERVER_PLIST)" >/dev/null 2>&1 || launchctl bootout "$$service" >/dev/null 2>&1; then echo "stopped launch agent $(APP_SERVER_LABEL)"; else echo "codex app-server launch agent was not loaded"; fi; rm -f "$(APP_SERVER_PID)"'

app-server-restart: app-server-stop app-server
