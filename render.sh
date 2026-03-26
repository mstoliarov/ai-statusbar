#!/usr/bin/env bash
# render.sh — reads state.json, renders status bar via gum

STATE="$HOME/.ai-statusbar/state.json"
JQ="$HOME/bin/jq"
GUM="$HOME/bin/gum"

[[ ! -f "$STATE" ]] && exit 0

# Read fields
MODEL=$("$JQ" -r '.model // "unknown"' "$STATE")
PROVIDER=$("$JQ" -r '.provider // "claude"' "$STATE")
TOKENS_IN=$("$JQ" -r '.tokens.input // 0' "$STATE")
TOKENS_OUT=$("$JQ" -r '.tokens.output // 0' "$STATE")
COST=$("$JQ" -r '.cost_usd // 0' "$STATE")
CTX=$("$JQ" -r '.tokens.context_used_pct // 0' "$STATE")
QUOTA=$("$JQ" -r '.quota_used_pct // 0' "$STATE")
TOOL=$("$JQ" -r '.tool.name // ""' "$STATE")
TOOL_STATUS=$("$JQ" -r '.tool.status // ""' "$STATE")
START_ISO=$("$JQ" -r '.session.start_iso // ""' "$STATE")
PROJECT_DIR=$("$JQ" -r '.session.project_dir // ""' "$STATE")

# Format tokens (abbreviate thousands) — no bc needed
fmt_num() {
  local n=$1
  if (( n >= 1000 )); then
    local whole=$(( n / 1000 ))
    local frac=$(( (n % 1000) / 100 ))
    echo "${whole}.${frac}k"
  else
    echo "$n"
  fi
}

TOKENS_IN_FMT=$(fmt_num "$TOKENS_IN")
TOKENS_OUT_FMT=$(fmt_num "$TOKENS_OUT")

# Format cost
COST_FMT=$(printf '%.4f' "$COST")

# Format duration
DURATION=""
if [[ -n "$START_ISO" && "$START_ISO" != "null" && "$START_ISO" != "" ]]; then
  START_EPOCH=$(date -d "$START_ISO" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S%z" "$START_ISO" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  if [[ "$START_EPOCH" -gt 0 ]]; then
    DIFF=$(( NOW_EPOCH - START_EPOCH ))
    MINS=$(( DIFF / 60 ))
    SECS=$(( DIFF % 60 ))
    DURATION="${MINS}m${SECS}s"
  fi
fi

# Format project dir (shorten home to ~)
if [[ -n "$PROJECT_DIR" && "$PROJECT_DIR" != "null" ]]; then
  HOME_ESCAPED=$(echo "$HOME" | sed 's/[\/&]/\\&/g')
  DIR=$(echo "$PROJECT_DIR" | sed "s|^$HOME_ESCAPED|~|")
else
  DIR=$(pwd | sed "s|^$HOME|~|")
fi

# Format tool
TOOL_LABEL=""
if [[ -n "$TOOL" && "$TOOL" != "null" && "$TOOL" != "" ]]; then
  if [[ "$TOOL_STATUS" == "done" ]]; then
    TOOL_LABEL="✓ $TOOL"
  else
    TOOL_LABEL="⟳ $TOOL"
  fi
fi

ICON="◈"

# Build segments
PARTS=()
[[ -n "$DIR" ]] && PARTS+=("📍 $DIR")
PARTS+=("$ICON $MODEL")
PARTS+=("↑${TOKENS_IN_FMT} ↓${TOKENS_OUT_FMT}")
PARTS+=("~\$$COST_FMT")
[[ -n "$DURATION" ]] && PARTS+=("⏱ $DURATION")
[[ "$CTX" -gt 0 ]] && PARTS+=("ctx ${CTX}%")
[[ "$QUOTA" -gt 0 ]] && PARTS+=("quota ${QUOTA}%")
[[ -n "$TOOL_LABEL" ]] && PARTS+=("$TOOL_LABEL")

# Join with separator
LINE=""
for i in "${!PARTS[@]}"; do
  if [[ $i -eq 0 ]]; then
    LINE="${PARTS[$i]}"
  else
    LINE="$LINE  │  ${PARTS[$i]}"
  fi
done

# Render with gum
"$GUM" style \
  --border normal \
  --border-foreground 240 \
  --foreground 252 \
  --padding "0 1" \
  --width 0 \
  "$LINE"
