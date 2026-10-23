#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$HOME/Library/Application Support/RednoteOCRBackend/LocalBackend"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
LOG_DIR="$RUNTIME_DIR/logs"
BRIDGE_PID_FILE="$RUNTIME_DIR/bridge.pid"
ADAPTER_PID_FILE="$RUNTIME_DIR/adapter.pid"
BRIDGE_LOG="$LOG_DIR/bridge.log"
ADAPTER_LOG="$LOG_DIR/adapter.log"
DEPLOY_LOG_DIR="$DEPLOY_DIR/runtime/logs"
LAUNCHD_BRIDGE_LOG="$DEPLOY_LOG_DIR/launchd-bridge.out.log"
LAUNCHD_ADAPTER_LOG="$DEPLOY_LOG_DIR/launchd-adapter.out.log"
LAUNCHD_BRIDGE_ERR_LOG="$DEPLOY_LOG_DIR/launchd-bridge.err.log"
LAUNCHD_ADAPTER_ERR_LOG="$DEPLOY_LOG_DIR/launchd-adapter.err.log"
VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python"
CLI_PATH="$SCRIPT_DIR/xiaohongshu-skills/scripts/cli.py"
BRIDGE_URL="ws://localhost:9333"
USER_DOMAIN="gui/$(id -u)"
BRIDGE_LABEL="com.chonggu.rednote.bridge"
ADAPTER_LABEL="com.chonggu.rednote.adapter"

mkdir -p "$LOG_DIR"

is_pid_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

read_pid() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] || return 1
    local pid
    pid="$(<"$pid_file")"
    [[ -n "$pid" ]] || return 1
    printf "%s" "$pid"
}

service_status() {
    local name="$1"
    local pid_file="$2"
    local launchd_label="${3:-}"

    if local pid="$(read_pid "$pid_file" 2>/dev/null)"; then
        if is_pid_running "$pid"; then
            echo "$name: running (pid $pid)"
            return 0
        fi
        rm -f "$pid_file"
    fi

    if [[ -n "$launchd_label" ]]; then
        if launchctl print "$USER_DOMAIN/$launchd_label" >/dev/null 2>&1; then
            local launchd_pid
            launchd_pid="$(
                launchctl print "$USER_DOMAIN/$launchd_label" 2>/dev/null |
                    awk '/pid = / { print $3; exit }'
            )"

            if [[ -n "$launchd_pid" && "$launchd_pid" != "0" ]]; then
                echo "$name: running via launchd (pid $launchd_pid)"
            else
                echo "$name: loaded via launchd"
            fi
            return 0
        fi
    fi

    echo "$name: stopped"
    return 1
}

start_service() {
    local name="$1"
    local pid_file="$2"
    local log_file="$3"
    local runner="$4"

    if local pid="$(read_pid "$pid_file" 2>/dev/null)"; then
        if is_pid_running "$pid"; then
            echo "$name is already running (pid $pid)."
            return 0
        fi
        rm -f "$pid_file"
    fi

    nohup "$runner" >>"$log_file" 2>&1 &
    local pid=$!
    echo "$pid" >"$pid_file"
    sleep 1

    if is_pid_running "$pid"; then
        echo "Started $name (pid $pid)."
        return 0
    fi

    echo "Failed to start $name. Recent log:"
    tail -n 20 "$log_file" || true
    rm -f "$pid_file"
    return 1
}

stop_service() {
    local name="$1"
    local pid_file="$2"

    if ! local pid="$(read_pid "$pid_file" 2>/dev/null)"; then
        echo "$name is already stopped."
        return 0
    fi

    if is_pid_running "$pid"; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        if is_pid_running "$pid"; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        echo "Stopped $name."
    else
        echo "$name was not running."
    fi

    rm -f "$pid_file"
}

print_login_status() {
    if [[ ! -x "$VENV_PYTHON" ]]; then
        echo "Login status: python environment missing at $VENV_PYTHON"
        return 1
    fi

    if [[ ! -f "$CLI_PATH" ]]; then
        echo "Login status: xiaohongshu-skills CLI missing at $CLI_PATH"
        return 1
    fi

    cd "$PROJECT_ROOT"
    "$VENV_PYTHON" "$CLI_PATH" --bridge-url "$BRIDGE_URL" check-login || true
}

tail_logs() {
    if [[ -d "$DEPLOY_LOG_DIR" ]]; then
        echo
        echo "== launchd-bridge.out.log =="
        tail -n 20 "$LAUNCHD_BRIDGE_LOG" 2>/dev/null || echo "(no launchd bridge stdout yet)"
        echo
        echo "== launchd-bridge.err.log =="
        tail -n 20 "$LAUNCHD_BRIDGE_ERR_LOG" 2>/dev/null || echo "(no launchd bridge stderr yet)"
        echo
        echo "== launchd-adapter.out.log =="
        tail -n 20 "$LAUNCHD_ADAPTER_LOG" 2>/dev/null || echo "(no launchd adapter stdout yet)"
        echo
        echo "== launchd-adapter.err.log =="
        tail -n 20 "$LAUNCHD_ADAPTER_ERR_LOG" 2>/dev/null || echo "(no launchd adapter stderr yet)"
    fi

    echo
    echo "== bridge.log =="
    tail -n 20 "$BRIDGE_LOG" 2>/dev/null || echo "(no bridge log yet)"
    echo
    echo "== adapter.log =="
    tail -n 20 "$ADAPTER_LOG" 2>/dev/null || echo "(no adapter log yet)"
}

usage() {
    cat <<'EOF'
Usage:
  ./LocalBackend/manage_services.sh start
  ./LocalBackend/manage_services.sh stop
  ./LocalBackend/manage_services.sh restart
  ./LocalBackend/manage_services.sh status
  ./LocalBackend/manage_services.sh login-status
  ./LocalBackend/manage_services.sh logs

What it manages:
  - bridge_server.py
  - adapter_server.py
EOF
}

command="${1:-status}"

case "$command" in
    start)
        start_service "bridge server" "$BRIDGE_PID_FILE" "$BRIDGE_LOG" "$SCRIPT_DIR/run_bridge.sh"
        start_service "adapter server" "$ADAPTER_PID_FILE" "$ADAPTER_LOG" "$SCRIPT_DIR/run_adapter.sh"
        ;;
    stop)
        stop_service "adapter server" "$ADAPTER_PID_FILE"
        stop_service "bridge server" "$BRIDGE_PID_FILE"
        ;;
    restart)
        stop_service "adapter server" "$ADAPTER_PID_FILE"
        stop_service "bridge server" "$BRIDGE_PID_FILE"
        start_service "bridge server" "$BRIDGE_PID_FILE" "$BRIDGE_LOG" "$SCRIPT_DIR/run_bridge.sh"
        start_service "adapter server" "$ADAPTER_PID_FILE" "$ADAPTER_LOG" "$SCRIPT_DIR/run_adapter.sh"
        ;;
    status)
        service_status "bridge server" "$BRIDGE_PID_FILE" "$BRIDGE_LABEL" || true
        service_status "adapter server" "$ADAPTER_PID_FILE" "$ADAPTER_LABEL" || true
        echo
        echo "Use './LocalBackend/manage_services.sh login-status' to check your Xiaohongshu login."
        ;;
    login-status)
        print_login_status
        ;;
    logs)
        tail_logs
        ;;
    *)
        usage
        exit 1
        ;;
esac
