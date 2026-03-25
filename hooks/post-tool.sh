#!/usr/bin/env bash
# Claude Code PostToolUse hook
# Receives JSON on stdin with tool_name, tool_input, tool_response

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
STATE="$HOME/.ai-statusbar/state.json"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

[[ -z "$TOOL_NAME" ]] && exit 0

# Initialize state.json if missing or invalid JSON
if [[ ! -f "$STATE" ]] || ! "$JQ" -e . "$STATE" &>/dev/null 2>&1; then
  echo '{"tool":{},"tokens":{"input":0,"output":0,"context_used_pct":0},"cost_usd":0,"quota_used_pct":0,"session":{"start_iso":"","project_dir":""},"usage":{},"requests_count":0,"lines_count":0,"claude_pid":0}' > "$STATE"
fi

# Update tool name/status
"$JQ" \
  --arg name "$TOOL_NAME" \
  '.tool.name = $name | .tool.status = "done"' \
  "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

# Session detection via PPID — reset requests_count if new Claude process
CURRENT_PID=$PPID
STORED_PID=$("$JQ" -r '.claude_pid // 0' "$STATE")
if [[ "$CURRENT_PID" != "$STORED_PID" ]]; then
  "$JQ" \
    --argjson pid "$CURRENT_PID" \
    '.claude_pid = $pid | .requests_count = 0 | .lines_count = 0' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
fi

# Increment request counter
"$JQ" \
  '.requests_count = ((.requests_count // 0) + 1)' \
  "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

# Count lines written for Write/Edit tools
if [[ "$TOOL_NAME" == "Write" ]]; then
  LINES=$(echo "$INPUT" | "$JQ" -r '.tool_input.content // ""' | wc -l)
  "$JQ" \
    --argjson l "$LINES" \
    '.lines_count = ((.lines_count // 0) + $l)' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  LINES=$(echo "$INPUT" | "$JQ" -r '.tool_input.new_string // ""' | wc -l)
  "$JQ" \
    --argjson l "$LINES" \
    '.lines_count = ((.lines_count // 0) + $l)' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
fi

bash "$HOME/.ai-statusbar/render.sh"
