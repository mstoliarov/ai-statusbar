#!/usr/bin/env bash
# configure.sh — interactive element selection for ai-statusbar
# Usage: bash ~/.ai-statusbar/configure.sh

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
GUM="$HOME/bin/gum"
CONFIG="$HOME/.ai-statusbar/config.json"

KEYS=(model context daily_limit weekly_limit tokens cost requests lines)
LABELS=(
  "Model name"
  "Context window usage"
  "Daily rate limit"
  "Weekly rate limit"
  "Token counter (session)"
  "Cost per session"
  "Total requests (session)"
  "Code lines written (session)"
)

# Read current enabled state for a key (default: true)
is_enabled() {
  local key=$1
  [ ! -f "$CONFIG" ] && echo "true" && return
  "$JQ" -r ".show.$key // true" "$CONFIG" 2>/dev/null
}

# Build comma-separated preselected labels
SELECTED=""
for i in "${!KEYS[@]}"; do
  if [ "$(is_enabled "${KEYS[$i]}")" = "true" ]; then
    [ -n "$SELECTED" ] && SELECTED+=","
    SELECTED+="${LABELS[$i]}"
  fi
done

# Show interactive multiselect
RESULT=$("$GUM" choose --no-limit \
  --header "Select status bar elements to display (space=toggle, enter=confirm):" \
  --selected="$SELECTED" \
  "${LABELS[@]}")

if [ $? -ne 0 ]; then
  echo "Cancelled — no changes made."
  exit 0
fi

# Build config JSON from selection result
new_config='{"show":{}}'
for i in "${!KEYS[@]}"; do
  key="${KEYS[$i]}"
  label="${LABELS[$i]}"
  if echo "$RESULT" | grep -qF "$label"; then
    val="true"
  else
    val="false"
  fi
  new_config=$(echo "$new_config" | "$JQ" --arg k "$key" --argjson v "$val" '.show[$k] = $v')
done

echo "$new_config" | "$JQ" '.' > "$CONFIG"
echo "Saved. Status bar will reflect changes immediately."
