#!/bin/zsh

set -euo pipefail

DEST_DIR="$HOME/Library/LaunchAgents"
DEPLOY_ROOT="$HOME/Library/Application Support/RednoteOCRBackend"
USER_DOMAIN="gui/$(id -u)"

remove_agent() {
    local filename="$1"
    local destination="$DEST_DIR/$filename"
    launchctl bootout "$USER_DOMAIN" "$destination" >/dev/null 2>&1 || true
    rm -f "$destination"
}

remove_agent "com.chonggu.rednote.bridge.plist"
remove_agent "com.chonggu.rednote.adapter.plist"
rm -rf "$DEPLOY_ROOT"

echo "Removed launch agents."
