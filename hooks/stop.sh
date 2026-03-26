#!/usr/bin/env bash
# Claude Code Stop hook
# Receives JSON on stdin with session usage data

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
STATE="$HOME/.ai-statusbar/state.json"

INPUT=$(cat)

# Extract model from Stop hook payload
MODEL=$(echo "$INPUT" | "$JQ" -r '.model // ""')

# Token counts — read from state.json (saved by statusline.sh from live JSON, more reliable than Stop payload)
TOKENS_IN=$("$JQ" -r '.tokens.input // 0' "$STATE")
TOKENS_OUT=$("$JQ" -r '.tokens.output // 0' "$STATE")

# Fallback: try Stop hook payload fields if state has 0
if [[ "$TOKENS_IN" == "0" ]]; then
  TOKENS_IN=$(echo "$INPUT" | "$JQ" -r '.usage.input_tokens // .session_stats.input_tokens // .input_tokens // 0')
fi
if [[ "$TOKENS_OUT" == "0" ]]; then
  TOKENS_OUT=$(echo "$INPUT" | "$JQ" -r '.usage.output_tokens // .session_stats.output_tokens // .output_tokens // 0')
fi

TOTAL_TOKENS=$(( TOKENS_IN + TOKENS_OUT ))

# Cost estimate: claude-sonnet pricing ~$3/$15 per 1M tokens
COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_IN * 3 + $TOKENS_OUT * 15) / 1000000 }")

# Context window % — sonnet context = 200k tokens
CONTEXT_TOTAL=200000
CTX_PCT=$(awk "BEGIN { printf \"%d\", ($TOKENS_IN + $TOKENS_OUT) * 100 / $CONTEXT_TOTAL }")
[[ "$CTX_PCT" -gt 100 ]] && CTX_PCT=100

# Daily / weekly usage tracking
TODAY=$(date +%Y-%m-%d)
WEEK_START=$(date -d "last Monday" +%Y-%m-%d 2>/dev/null || date -v-Mon +%Y-%m-%d 2>/dev/null || echo "$TODAY")

STORED_TODAY=$("$JQ" -r '.usage.today // ""' "$STATE")
STORED_WEEK_START=$("$JQ" -r '.usage.week_start // ""' "$STATE")

# If same day → add tokens; otherwise reset daily counter
if [[ "$STORED_TODAY" == "$TODAY" ]]; then
  TODAY_TOKENS=$("$JQ" -r ".usage.today_tokens // 0" "$STATE")
  TODAY_TOKENS=$(( TODAY_TOKENS + TOTAL_TOKENS ))
else
  TODAY_TOKENS=$TOTAL_TOKENS
fi

# If same week → add tokens; otherwise reset weekly counter
if [[ "$STORED_WEEK_START" == "$WEEK_START" ]]; then
  WEEK_TOKENS=$("$JQ" -r ".usage.week_tokens // 0" "$STATE")
  WEEK_TOKENS=$(( WEEK_TOKENS + TOTAL_TOKENS ))
else
  WEEK_TOKENS=$TOTAL_TOKENS
fi

# Update state (no counter reset — counters persist per Claude process via PPID in post-tool.sh)
"$JQ" \
  --argjson ti "$TOKENS_IN" \
  --argjson to "$TOKENS_OUT" \
  --argjson cost "$COST" \
  --argjson ctx "$CTX_PCT" \
  --arg model "$MODEL" \
  --arg dir "$(pwd)" \
  --arg today "$TODAY" \
  --argjson today_tok "$TODAY_TOKENS" \
  --arg week_start "$WEEK_START" \
  --argjson week_tok "$WEEK_TOKENS" \
  '.tokens.input = $ti |
   .tokens.output = $to |
   .cost_usd = $cost |
   .tokens.context_used_pct = $ctx |
   (if $model != "" then .model = $model else . end) |
   .provider = "claude" |
   .session.project_dir = $dir |
   (if .session.start_iso == "" then .session.start_iso = now | todate else . end) |
   .usage.today = $today |
   .usage.today_tokens = $today_tok |
   .usage.week_start = $week_start |
   .usage.week_tokens = $week_tok' \
  "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
