#!/usr/bin/env bash
set -euo pipefail

PROFILE_HOME="${1:-}"
if [ -z "$PROFILE_HOME" ]; then
  echo "Usage: install-profile.sh <hermes-profile-home> [--no-launchctl]" >&2
  exit 2
fi
if [ ! -d "$PROFILE_HOME" ]; then
  echo "Profile path not found: $PROFILE_HOME" >&2
  exit 2
fi

USE_LAUNCHCTL=1

shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-launchctl)
      USE_LAUNCHCTL=0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: install-profile.sh <hermes-profile-home> [--no-launchctl]" >&2
      exit 2
      ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_NAME="$(basename "$PROFILE_HOME")"
SKILL_SRC="$REPO_DIR/skill"
SKILL_DST="$PROFILE_HOME/skills/productivity/hermes-cron-notification"
LEGACY_SKILL_DST="$PROFILE_HOME/skills/productivity/hermes-scheduler"
SCHEDULER_SRC="$REPO_DIR/scheduler"
SCHEDULER_DST="$PROFILE_HOME/scheduler"
BIN_DST="$PROFILE_HOME/bin/hcron"
CONFIG_DST="$PROFILE_HOME/config.yaml"
CRON_DIR="$PROFILE_HOME/cron"
SCHEDULE_DST="$CRON_DIR/schedule.json"
TARGETS_DST="$SCHEDULER_DST/notification-targets.json"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_DST="$LAUNCH_AGENTS_DIR/ai.hermes.cron-notification-${PROFILE_NAME}.plist"
LAUNCH_LABEL="ai.hermes.cron-notification-${PROFILE_NAME}"
LEGACY_PLIST_DST="$LAUNCH_AGENTS_DIR/ai.hermes.scheduler-${PROFILE_NAME}.plist"
LEGACY_LAUNCH_LABEL="ai.hermes.scheduler-${PROFILE_NAME}"
LOG_DIR="$PROFILE_HOME/logs"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -z "$NODE_BIN" ]; then
  NODE_BIN="/opt/homebrew/bin/node"
fi

mkdir -p "$PROFILE_HOME/skills/productivity" "$PROFILE_HOME/bin" "$CRON_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
rm -rf "$SKILL_DST"
rm -rf "$LEGACY_SKILL_DST"
cp -R "$SKILL_SRC" "$SKILL_DST"
mkdir -p "$SCHEDULER_DST/scripts"
cp -R "$SCHEDULER_SRC/scripts/." "$SCHEDULER_DST/scripts/"

find "$SCHEDULER_DST/scripts" -type f \( -name "*.sh" -o -name "*.js" \) -exec chmod +x {} +

cat > "$BIN_DST" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export HERMES_HOME="\${HERMES_HOME:-$PROFILE_HOME}"
exec bash "\$HERMES_HOME/scheduler/scripts/hcron.sh" "\$@"
EOF
chmod +x "$BIN_DST"

if [ ! -f "$SCHEDULE_DST" ]; then
  cat > "$SCHEDULE_DST" <<'EOF'
{
  "jobs": [],
  "lastUpdated": ""
}
EOF
fi

if [ ! -f "$TARGETS_DST" ]; then
  cp "$REPO_DIR/templates/notification-targets.json" "$TARGETS_DST"
fi

python3 - "$SCHEDULE_DST" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(data.get("jobs"), list):
    data["jobs"] = []
data["lastUpdated"] = data.get("lastUpdated") or ""
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

python3 - "$CONFIG_DST" "$PROFILE_HOME" <<'PY'
import sys
from pathlib import Path
import re

config_path = Path(sys.argv[1])
profile_home = sys.argv[2]

entries = {
    "remind-add": f"{profile_home}/bin/hcron add {{args}}",
    "remind_add": f"{profile_home}/bin/hcron add {{args}}",
    "remind-list": f"{profile_home}/bin/hcron list",
    "remind_list": f"{profile_home}/bin/hcron list",
    "remind-cancel": f"{profile_home}/bin/hcron cancel {{args}}",
    "remind_cancel": f"{profile_home}/bin/hcron cancel {{args}}",
    "remind-enable": f"{profile_home}/bin/hcron enable {{args}}",
    "remind_enable": f"{profile_home}/bin/hcron enable {{args}}",
    "remind-disable": f"{profile_home}/bin/hcron disable {{args}}",
    "remind_disable": f"{profile_home}/bin/hcron disable {{args}}",
}

content = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
if "quick_commands:" not in content:
    block = ["quick_commands:"]
    for key, command in entries.items():
        block.extend(
            [
                f"  {key}:",
                "    type: exec",
                f"    command: {command}",
            ]
        )
    new_content = content.rstrip()
    if new_content:
        new_content += "\n"
    new_content += "\n".join(block) + "\n"
    config_path.write_text(new_content, encoding="utf-8")
    raise SystemExit(0)

for key, command in entries.items():
    pattern = re.compile(
        rf"(?ms)^  {re.escape(key)}:\n(?:    .*\n)*?(?=^  [^ \n][^:]*:\n|^[^ \t].*:\n|\Z)"
    )
    replacement = f"  {key}:\n    type: exec\n    command: {command}\n"
    if pattern.search(content):
        content = pattern.sub(replacement, content, count=1)
    else:
        anchor = re.search(r"(?m)^quick_commands:\n", content)
        if anchor:
            insert_at = anchor.end()
            content = content[:insert_at] + replacement + content[insert_at:]

config_path.write_text(content.rstrip() + "\n", encoding="utf-8")
PY

cat > "$PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LAUNCH_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${PROFILE_HOME}/scheduler/scripts/scheduler-runner.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HERMES_HOME</key>
      <string>${PROFILE_HOME}</string>
      <key>NODE_BIN</key>
      <string>${NODE_BIN}</string>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/Users/sscomp/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>${PROFILE_HOME}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>StandardOutPath</key>
    <string>${PROFILE_HOME}/logs/cron-notification.launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${PROFILE_HOME}/logs/cron-notification.launchd.error.log</string>
  </dict>
</plist>
EOF

if [ "$USE_LAUNCHCTL" -eq 1 ] && [ -n "${NODE_BIN:-}" ] && [ -x "$(command -v launchctl || true)" ]; then
  launchctl bootout "gui/$(id -u)/${LEGACY_LAUNCH_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/${LAUNCH_LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
  launchctl kickstart -k "gui/$(id -u)/${LAUNCH_LABEL}" >/dev/null 2>&1 || true
fi

rm -f "$LEGACY_PLIST_DST"

echo "Installed Hermes Cron Notification into: $PROFILE_HOME"
echo "  skill: $SKILL_DST"
echo "  scheduler: $SCHEDULER_DST"
echo "  wrapper: $BIN_DST"
echo "  schedule: $SCHEDULE_DST"
echo "  targets: $TARGETS_DST"
echo "  launch agent: $PLIST_DST"
echo "  legacy skill removed: $LEGACY_SKILL_DST"
echo "  legacy launch agent removed: $LEGACY_PLIST_DST"
if [ "$USE_LAUNCHCTL" -eq 1 ]; then
  echo "  launchctl: reloaded"
else
  echo "  launchctl: skipped (--no-launchctl)"
fi
echo "Next step: test $PROFILE_HOME/bin/hcron list or /remind-list."
