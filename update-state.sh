#!/usr/bin/env bash
# update-state.sh <jq_path> <value>
# Example: update-state.sh .model '"gemini-2.5-pro"'
# Example: update-state.sh .tokens.input 1234

STATE="$HOME/.ai-statusbar/state.json"
JQ="$HOME/bin/jq"

if [[ -z "$1" || -z "$2" ]]; then
  echo "Usage: update-state.sh <jq_path> <value>" >&2
  exit 1
fi

"$JQ" --argjson v "$2" "$1 = \$v" "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
