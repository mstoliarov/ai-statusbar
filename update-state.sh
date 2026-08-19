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

# $1 is interpolated into the jq filter, so restrict it to a plain
# dotted/bracket path (e.g. .model, .tokens.input, .foo[0]) to avoid
# arbitrary jq filter injection via the argument.
if ! [[ "$1" =~ ^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]+\])*$ ]]; then
  echo "Invalid jq_path: $1" >&2
  exit 1
fi

"$JQ" --argjson v "$2" "$1 = \$v" "$STATE" > "${STATE}.$$" && mv "${STATE}.$$" "$STATE"
