#!/usr/bin/env bash

set -euo pipefail

if [ -z "${HERMES_HOME:-}" ]; then
  echo "Missing HERMES_HOME."
  exit 1
fi

NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -z "$NODE_BIN" ]; then
  echo "Missing node binary. Set NODE_BIN or install node." >&2
  exit 1
fi

SCRIPT_DIR="$HERMES_HOME/scheduler/scripts"
ADD_SCRIPT="$SCRIPT_DIR/add-schedule.js"
RUNNER_SCRIPT="$SCRIPT_DIR/scheduler-runner.sh"

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  echo "Usage: hcron <add|list|cancel|enable|disable|tick> [args...]" >&2
  exit 2
fi
shift || true

case "$COMMAND" in
  add|list|cancel|enable|disable)
    exec "$NODE_BIN" "$ADD_SCRIPT" "$COMMAND" "$@"
    ;;
  tick)
    exec /bin/bash "$RUNNER_SCRIPT"
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: hcron <add|list|cancel|enable|disable|tick> [args...]" >&2
    exit 2
    ;;
esac
