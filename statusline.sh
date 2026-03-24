#!/usr/bin/env bash
# Claude Code inline status line — progress bar + counters
# Part of ai-statusbar plugin: https://github.com/maxstab/ai-statusbar
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

# --- Context window usage ---
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // 0')
used_pct_int=$(printf "%.0f" "$used_pct")

if [ "$used_pct_int" -ge 80 ]; then
  ctx_color="$RED"
elif [ "$used_pct_int" -ge 50 ]; then
  ctx_color="$YELLOW"
else
  ctx_color="$GREEN"
fi

bar=$(make_bar "$used_pct_int")

# --- Counters from state.json ---
STATE="$HOME/.ai-statusbar/state.json"
requests=0
lines=0
if [ -f "$STATE" ]; then
  requests=$("$JQ" -r '.requests_count // 0' "$STATE" 2>/dev/null || echo 0)
  lines=$("$JQ" -r '.lines_count // 0' "$STATE" 2>/dev/null || echo 0)
fi

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

# Progress bar + usage %
out+="${ctx_color}${bar} ${used_pct_int}%${RESET}${SEP}"

# Requests counter
out+="${BLUE}🔧 ${requests} req${RESET}${SEP}"

# Lines of code counter
out+="${DIM}📝 ${lines} lines${RESET}"

printf "%b" "$out"
