#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
LOG_DIR="$RUNTIME_DIR/logs"

mkdir -p "$LOG_DIR"

cd "$PROJECT_ROOT"

exec "$SCRIPT_DIR/.venv/bin/python" \
    "$SCRIPT_DIR/adapter_server.py"
