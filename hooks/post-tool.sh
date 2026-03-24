#!/usr/bin/env bash
# Claude Code PostToolUse hook
# Receives JSON on stdin with tool_name, tool_input, tool_response

export PATH="$HOME/bin:$PATH"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

[[ -z "$TOOL_NAME" ]] && exit 0

# Update state
echo "$INPUT" | jq -r --arg t "$TOOL_NAME" '{"tool_name": $t, "status": "done"}' > /dev/null
"$HOME/bin/jq" \
  --arg name "$TOOL_NAME" \
  '.tool.name = $name | .tool.status = "done"' \
  "$HOME/.ai-statusbar/state.json" > "$HOME/.ai-statusbar/state.json.tmp" \
  && mv "$HOME/.ai-statusbar/state.json.tmp" "$HOME/.ai-statusbar/state.json"

# Increment request counter
"$HOME/bin/jq" \
  '.requests_count = ((.requests_count // 0) + 1)' \
  "$HOME/.ai-statusbar/state.json" > "$HOME/.ai-statusbar/state.json.tmp" \
  && mv "$HOME/.ai-statusbar/state.json.tmp" "$HOME/.ai-statusbar/state.json"

# Count lines written for Write/Edit tools
if [[ "$TOOL_NAME" == "Write" ]]; then
  LINES=$(echo "$INPUT" | "$HOME/bin/jq" -r '.tool_input.content // ""' | wc -l)
  "$HOME/bin/jq" \
    --argjson l "$LINES" \
    '.lines_count = ((.lines_count // 0) + $l)' \
    "$HOME/.ai-statusbar/state.json" > "$HOME/.ai-statusbar/state.json.tmp" \
    && mv "$HOME/.ai-statusbar/state.json.tmp" "$HOME/.ai-statusbar/state.json"
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  LINES=$(echo "$INPUT" | "$HOME/bin/jq" -r '.tool_input.new_string // ""' | wc -l)
  "$HOME/bin/jq" \
    --argjson l "$LINES" \
    '.lines_count = ((.lines_count // 0) + $l)' \
    "$HOME/.ai-statusbar/state.json" > "$HOME/.ai-statusbar/state.json.tmp" \
    && mv "$HOME/.ai-statusbar/state.json.tmp" "$HOME/.ai-statusbar/state.json"
fi

bash "$HOME/.ai-statusbar/render.sh"
