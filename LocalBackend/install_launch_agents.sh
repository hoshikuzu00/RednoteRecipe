#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/launchd"
DEST_DIR="$HOME/Library/LaunchAgents"
DEPLOY_ROOT="$HOME/Library/Application Support/RednoteOCRBackend"
DEPLOY_DIR="$DEPLOY_ROOT/LocalBackend"
LOG_DIR="$DEPLOY_DIR/runtime/logs"
USER_DOMAIN="gui/$(id -u)"
BOOTSTRAP_PYTHON="$SCRIPT_DIR/.venv/bin/python"

mkdir -p "$DEST_DIR" "$LOG_DIR"

render_plist() {
    local template="$1"
    local destination="$2"

    sed \
        -e "s|__DEPLOYED_BACKEND_DIR__|$DEPLOY_DIR|g" \
        "$template" >"$destination"
}

stop_agent() {
    local destination="$1"
    launchctl bootout "$USER_DOMAIN" "$destination" >/dev/null 2>&1 || true
}

prepare_deploy_dir() {
    mkdir -p "$DEPLOY_ROOT"

    rsync -a --delete \
        --exclude ".venv/" \
        --exclude "runtime/" \
        --exclude "__pycache__/" \
        --exclude "*.pyc" \
        "$SCRIPT_DIR/" "$DEPLOY_DIR/"

    mkdir -p "$DEPLOY_DIR/runtime/logs"
}

prepare_deploy_env() {
    local deploy_python="$DEPLOY_DIR/.venv/bin/python"
    local deploy_pip="$DEPLOY_DIR/.venv/bin/pip"

    if [[ ! -x "$BOOTSTRAP_PYTHON" ]]; then
        BOOTSTRAP_PYTHON="$(command -v python3)"
    fi

    if [[ -z "${BOOTSTRAP_PYTHON:-}" || ! -x "$BOOTSTRAP_PYTHON" ]]; then
        echo "Could not find a Python 3 interpreter to bootstrap the deployed backend." >&2
        exit 1
    fi

    if [[ ! -x "$deploy_python" ]]; then
        "$BOOTSTRAP_PYTHON" -m venv "$DEPLOY_DIR/.venv"
    fi

    "$deploy_pip" install --disable-pip-version-check -q -r "$DEPLOY_DIR/requirements.txt"
}

install_agent() {
    local template_name="$1"
    local destination_name="$2"
    local label="$3"

    local template="$LAUNCHD_DIR/$template_name"
    local destination="$DEST_DIR/$destination_name"

    render_plist "$template" "$destination"
    launchctl bootstrap "$USER_DOMAIN" "$destination"
    launchctl kickstart -k "$USER_DOMAIN/$label"
}

stop_agent "$DEST_DIR/com.chonggu.rednote.bridge.plist"
stop_agent "$DEST_DIR/com.chonggu.rednote.adapter.plist"
prepare_deploy_dir
prepare_deploy_env
install_agent "com.chonggu.rednote.bridge.plist.template" "com.chonggu.rednote.bridge.plist" "com.chonggu.rednote.bridge"
install_agent "com.chonggu.rednote.adapter.plist.template" "com.chonggu.rednote.adapter.plist" "com.chonggu.rednote.adapter"

echo "Installed launch agents."
echo "Bridge and adapter will now start automatically when you log in."
echo "They now run from: $DEPLOY_DIR"
echo
echo "You can still check status with:"
echo "  ./LocalBackend/manage_services.sh status"
