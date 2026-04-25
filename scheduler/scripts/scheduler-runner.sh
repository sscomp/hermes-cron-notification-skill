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

LOG_FILE="$HERMES_HOME/cron/scheduler.log"
LOCK_DIR="$HERMES_HOME/cron/.scheduler.lock"
RUN_DUE="$HERMES_HOME/scheduler/scripts/run-due.js"

mkdir -p "$HERMES_HOME/cron"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Previous scheduler tick still running." >> "$LOG_FILE"
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scheduler tick start: $HERMES_HOME"
  "$NODE_BIN" "$RUN_DUE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scheduler tick done"
} >> "$LOG_FILE" 2>&1
