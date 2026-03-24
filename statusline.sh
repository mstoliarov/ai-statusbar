#!/usr/bin/env bash
# Claude Code inline status line — progress bar + counters + usage
# Part of ai-statusbar plugin: https://github.com/mstoliarov/ai-statusbar
# Receives JSON via stdin from Claude Code

export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"
input=$(cat)

# ANSI colors
RESET="\033[0m"
BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"
BLUE="\033[34m"
DIM="\033[2m"

# Progress bar generator (width=10)
make_bar() {
  local pct=$1
  local width=10
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  printf "%s" "$bar"
}

# Color by percentage thresholds (for ctx only)
pct_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then echo "$RED"
  elif [ "$pct" -ge 50 ]; then echo "$YELLOW"
  else echo "$GREEN"
  fi
}

# Format large numbers: 1234567 → 1.2M, 45000 → 45k
fmt_num() {
  local n=$1
  awk "BEGIN {
    if ($n >= 1000000) printf \"%.1fM\", $n/1000000
    else if ($n >= 1000) printf \"%.0fk\", $n/1000
    else printf \"%d\", $n
  }"
}

# --- Working directory ---
cwd=$(echo "$input" | "$JQ" -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
folder=$(basename "$cwd")

# --- Git branch and status ---
git_branch=""
git_color="$GREEN"
git_status_indicator=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  git_dirty=$(git -C "$cwd" status --porcelain 2>/dev/null)
  if [ -n "$git_dirty" ]; then
    git_status_indicator="*"
    git_color="$YELLOW"
  fi
fi

# --- Model name (shorten) ---
model=$(echo "$input" | "$JQ" -r '.model.display_name // empty')
model_short=$(echo "$model" | sed 's/Claude //i' | sed 's/ (.*)//')

# --- Context window ---
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // 0')
used_pct_int=$(printf "%.0f" "$used_pct")
ctx_color=$(pct_color "$used_pct_int")
ctx_bar=$(make_bar "$used_pct_int")
ctx_size=$(echo "$input" | "$JQ" -r '.context_window.max_tokens // 200000')
ctx_size_fmt=$(fmt_num "$ctx_size")

# Token counts — read directly from statusLine JSON (most accurate)
tok_in=$(echo "$input" | "$JQ" -r '.context_window.total_input_tokens // 0')
tok_out=$(echo "$input" | "$JQ" -r '.context_window.total_output_tokens // 0')
tok_total=$(( tok_in + tok_out ))
tok_fmt=$(fmt_num "$tok_total")

# --- State.json ---
STATE="$HOME/.ai-statusbar/state.json"
requests=0
lines=0
today_tokens=0
week_tokens=0
daily_limit=1000000
weekly_limit=5000000

if [ -f "$STATE" ]; then
  requests=$("$JQ" -r '.requests_count // 0' "$STATE" 2>/dev/null || echo 0)
  lines=$("$JQ" -r '.lines_count // 0' "$STATE" 2>/dev/null || echo 0)
  today_tokens=$("$JQ" -r '.usage.today_tokens // 0' "$STATE" 2>/dev/null || echo 0)
  week_tokens=$("$JQ" -r '.usage.week_tokens // 0' "$STATE" 2>/dev/null || echo 0)
  daily_limit=$("$JQ" -r '.usage.daily_limit // 1000000' "$STATE" 2>/dev/null || echo 1000000)
  weekly_limit=$("$JQ" -r '.usage.weekly_limit // 5000000' "$STATE" 2>/dev/null || echo 5000000)
fi

# --- Usage/d ---
day_pct=$(awk "BEGIN { v = int($today_tokens * 100 / $daily_limit); print (v > 100 ? 100 : v) }")
day_bar=$(make_bar "$day_pct")
day_limit_fmt=$(fmt_num "$daily_limit")
day_used_fmt=$(fmt_num "$today_tokens")

# --- Usage/w ---
week_pct=$(awk "BEGIN { v = int($week_tokens * 100 / $weekly_limit); print (v > 100 ? 100 : v) }")
week_bar=$(make_bar "$week_pct")
week_limit_fmt=$(fmt_num "$weekly_limit")
week_used_fmt=$(fmt_num "$week_tokens")

# --- Build output ---
SEP="${DIM} │ ${RESET}"
out=""

# Folder + git
out+="${BOLD}${CYAN}${folder}${RESET}"
if [ -n "$git_branch" ]; then
  out+=" ${git_color}[${git_branch}${git_status_indicator}]${RESET}"
fi
out+="${SEP}"

# Model
if [ -n "$model_short" ]; then
  out+="${MAGENTA}${model_short}${RESET}${SEP}"
fi

# ctx — threshold colors
out+="${DIM}ctx${RESET} ${ctx_color}${ctx_bar} ${used_pct_int}% / ${ctx_size_fmt}${RESET}${SEP}"

# usage/d — blue
out+="${DIM}usage/d${RESET} ${BLUE}${day_bar} ${day_pct}% / ${day_limit_fmt}${RESET}${SEP}"

# usage/w — blue
out+="${DIM}usage/w${RESET} ${BLUE}${week_bar} ${week_pct}% / ${week_limit_fmt}${RESET}${SEP}"

# Token counter (from statusLine JSON — live, accurate)
out+="${DIM}tok${RESET} ${CYAN}${tok_fmt}${RESET}${SEP}"

# Requests counter
out+="${BLUE}🔧 ${requests} req${RESET}${SEP}"

# Lines of code counter
out+="${DIM}📝 ${lines} lines${RESET}"

printf "%b" "$out"
