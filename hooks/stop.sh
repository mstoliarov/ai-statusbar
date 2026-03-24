#!/usr/bin/env bash
# Claude Code Stop hook
# Receives JSON on stdin with session usage data

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
STATE="$HOME/.ai-statusbar/state.json"

INPUT=$(cat)

# Extract fields — Claude Code Stop hook payload
TOKENS_IN=$(echo "$INPUT" | "$JQ" -r '.usage.input_tokens // .session_stats.input_tokens // 0')
TOKENS_OUT=$(echo "$INPUT" | "$JQ" -r '.usage.output_tokens // .session_stats.output_tokens // 0')
MODEL=$(echo "$INPUT" | "$JQ" -r '.model // ""')

# Fallback: try top-level keys
[[ "$TOKENS_IN" == "0" ]] && TOKENS_IN=$(echo "$INPUT" | "$JQ" -r '.input_tokens // 0')
[[ "$TOKENS_OUT" == "0" ]] && TOKENS_OUT=$(echo "$INPUT" | "$JQ" -r '.output_tokens // 0')

# Cost estimate: claude-sonnet pricing ~$3/$15 per 1M tokens
COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_IN * 3 + $TOKENS_OUT * 15) / 1000000 }")

# Context window % — sonnet context = 200k tokens, 1% = 2000 tokens
CONTEXT_TOTAL=200000
CTX_PCT=$(awk "BEGIN { printf \"%d\", ($TOKENS_IN + $TOKENS_OUT) * 100 / $CONTEXT_TOTAL }")
[[ "$CTX_PCT" -gt 100 ]] && CTX_PCT=100

# Update state
"$JQ" \
  --argjson ti "$TOKENS_IN" \
  --argjson to "$TOKENS_OUT" \
  --argjson cost "$COST" \
  --argjson ctx "$CTX_PCT" \
  --arg model "$MODEL" \
  --arg dir "$(pwd)" \
  '.tokens.input = $ti |
   .tokens.output = $to |
   .cost_usd = $cost |
   .tokens.context_used_pct = $ctx |
   (if $model != "" then .model = $model else . end) |
   .provider = "claude" |
   .session.project_dir = $dir |
   (if .session.start_iso == "" then .session.start_iso = now | todate else . end)' \
  "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

# Reset session counters
"$JQ" \
  '.requests_count = 0 | .lines_count = 0' \
  "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

bash "$HOME/.ai-statusbar/render.sh"
