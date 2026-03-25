#!/usr/bin/env bash
# toggle.sh — enable/disable statusLine in ~/.claude/settings.json

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
SETTINGS="$HOME/.claude/settings.json"

if "$JQ" -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
  "$JQ" 'del(.statusLine)' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "disabled"
else
  "$JQ" '.statusLine = {"type": "command", "command": "bash ~/.ai-statusbar/statusline.sh"}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "enabled"
fi
