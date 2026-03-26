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

# Color by percentage thresholds
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

# --- Model ---
model=$(echo "$input" | "$JQ" -r '.model.display_name // empty')
model_short=$(echo "$model" | sed 's/Claude //i' | sed 's/ (.*)//')


# --- RAM: system + Claude process (cached 30s on Windows) ---
RAM_CACHE="$HOME/.ai-statusbar/.ram_cache"
ram_pct=0; ram_used_gb="0"; ram_total_gb="0"; claude_ram_mb="0"; claude_ram_pct=0

read_ram() {
  if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OS" == "Windows_NT" ]]; then
    # Single PowerShell call: system RAM + Claude process RAM (found by command line)
    powershell -NoProfile -Command "
      \$os = Get-CimInstance Win32_OperatingSystem
      \$totalKB = \$os.TotalVisibleMemorySize
      \$freeKB = \$os.FreePhysicalMemory
      \$cMB = 0
      \$cp = Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { \$_.CommandLine -match 'claude-code' } | Select-Object -First 1
      if (\$cp) { try { \$cMB = [math]::Round((Get-Process -Id \$cp.ProcessId).WorkingSet64 / 1MB) } catch {} }
      \"\$totalKB \$freeKB \$cMB\"
    " 2>/dev/null | awk '{
      used=$1-$2; pct=int(used*100/$1)
      ug=used/1048576; tg=$1/1048576
      cMB=$3; cpct=int(cMB*1024*100/$1)
      printf "%d %.1f %.0f %d %d", pct, ug, tg, cMB, cpct
    }'
  elif [ -f /proc/meminfo ]; then
    # Linux: find Claude by command line
    local c_kb=0
    local cpid
    cpid=$(pgrep -f 'claude-code/cli' 2>/dev/null | head -1)
    if [ -n "$cpid" ] && [ -f "/proc/$cpid/status" ]; then
      c_kb=$(awk '/^VmRSS:/{print $2}' "/proc/$cpid/status" 2>/dev/null)
    fi
    c_kb=${c_kb:-0}
    awk -v ckb="$c_kb" '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{
      u=t-a; pct=int(u*100/t)
      cMB=int(ckb/1024); cpct=int(ckb*100/t)
      printf "%d %.1f %.0f %d %d", pct, u/1048576, t/1048576, cMB, cpct
    }' /proc/meminfo
  fi
}

# Use cache if fresh (< 30s), otherwise refresh
use_cache=0
if [ -f "$RAM_CACHE" ]; then
  cache_age=$(( $(date +%s) - $(date -r "$RAM_CACHE" +%s 2>/dev/null || stat -c %Y "$RAM_CACHE" 2>/dev/null || echo 0) ))
  [ "$cache_age" -lt 30 ] && use_cache=1
fi

if [ "$use_cache" = "1" ]; then
  read ram_pct ram_used_gb ram_total_gb claude_ram_mb claude_ram_pct < "$RAM_CACHE"
else
  ram_data=$(read_ram "$claude_pid")
  if [ -n "$ram_data" ]; then
    echo "$ram_data" > "$RAM_CACHE"
    read ram_pct ram_used_gb ram_total_gb claude_ram_mb claude_ram_pct <<< "$ram_data"
  fi
fi

ram_bar=$(make_bar "$ram_pct")
ram_color=$(pct_color "$ram_pct")
claude_ram_bar=$(make_bar "$claude_ram_pct")
claude_ram_color=$(pct_color "$claude_ram_pct")

# --- Context window ---
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // 0')
used_pct_int=$(printf "%.0f" "$used_pct")
ctx_color=$(pct_color "$used_pct_int")
ctx_bar=$(make_bar "$used_pct_int")
ctx_size=$(echo "$input" | "$JQ" -r '.context_window.context_window_size // 200000')
ctx_size_fmt=$(fmt_num "$ctx_size")

# --- Token counts (live from statusLine JSON) ---
tok_in=$(echo "$input" | "$JQ" -r '.context_window.total_input_tokens // 0')
tok_out=$(echo "$input" | "$JQ" -r '.context_window.total_output_tokens // 0')
tok_total=$(( tok_in + tok_out ))
tok_fmt=$(fmt_num "$tok_total")

# --- Rate limits (matches /usage dialog exactly) ---
usage_5h=$(echo "$input" | "$JQ" -r '.rate_limits.five_hour.used_percentage // 0')
usage_5h_int=$(printf "%.0f" "$usage_5h")
usage_5h_bar=$(make_bar "$usage_5h_int")

usage_7d=$(echo "$input" | "$JQ" -r '.rate_limits.seven_day.used_percentage // 0')
usage_7d_int=$(printf "%.0f" "$usage_7d")
usage_7d_bar=$(make_bar "$usage_7d_int")

# --- Cost ---
cost=$(echo "$input" | "$JQ" -r '.cost.total_cost_usd // 0')
cost_fmt=$(awk "BEGIN { printf \"%.2f\", $cost }")

# --- Lines (from Claude Code's own counter) ---
lines_added=$(echo "$input" | "$JQ" -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | "$JQ" -r '.cost.total_lines_removed // 0')

# --- Request counter from state.json (PPID-based session) ---
STATE="$HOME/.ai-statusbar/state.json"
requests=0
if [ -f "$STATE" ]; then
  requests=$("$JQ" -r '.requests_count // 0' "$STATE" 2>/dev/null || echo 0)
fi

# --- Element visibility config ---
CONFIG="$HOME/.ai-statusbar/config.json"
CONFIG_SHOW=""
if [ -f "$CONFIG" ]; then
  CONFIG_SHOW=$("$JQ" -r '.show | to_entries[] | "\(.key)=\(.value)"' "$CONFIG" 2>/dev/null)
fi

# Returns 1 if element should be shown (default: show all when no config)
show_el() {
  [ -z "$CONFIG_SHOW" ] && echo 1 && return
  local val
  val=$(echo "$CONFIG_SHOW" | grep "^${1}=" | cut -d= -f2)
  [ "$val" = "false" ] && echo 0 || echo 1
}

# Save live token counts to state.json for stop.sh daily/weekly accumulation
if [ "$tok_total" -gt 0 ] && [ -f "$STATE" ]; then
  "$JQ" --argjson ti "$tok_in" --argjson to "$tok_out" \
    '.tokens.input = $ti | .tokens.output = $to' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
fi

# --- Build output ---
SEP="${DIM} │ ${RESET}"
segments=()

# Folder + git (always shown)
seg="${BOLD}${CYAN}${folder}${RESET}"
if [ -n "$git_branch" ]; then
  seg+=" ${git_color}[${git_branch}${git_status_indicator}]${RESET}"
fi
segments+=("$seg")

# Model
if [ -n "$model_short" ] && [ "$(show_el model)" = "1" ]; then
  segments+=("${MAGENTA}${model_short}${RESET}")
fi


# ctx — threshold colors
if [ "$(show_el context)" = "1" ]; then
  segments+=("${DIM}ctx${RESET} ${ctx_color}${ctx_bar} ${used_pct_int}% / ${ctx_size_fmt}${RESET}")
fi

# usage/d — 5h rate limit (matches /usage "Current session")
if [ "$(show_el daily_limit)" = "1" ]; then
  segments+=("${DIM}usage/d${RESET} ${BLUE}${usage_5h_bar} ${usage_5h_int}%${RESET}")
fi

# usage/w — 7d rate limit (matches /usage "Current week")
if [ "$(show_el weekly_limit)" = "1" ]; then
  segments+=("${DIM}usage/w${RESET} ${BLUE}${usage_7d_bar} ${usage_7d_int}%${RESET}")
fi

# Token counter
if [ "$(show_el tokens)" = "1" ]; then
  segments+=("${DIM}tok${RESET} ${CYAN}${tok_fmt}${RESET}")
fi

# Cost
if [ "$(show_el cost)" = "1" ]; then
  segments+=("${DIM}\$${cost_fmt}${RESET}")
fi

# Requests counter
if [ "$(show_el requests)" = "1" ]; then
  segments+=("${BLUE}🔧 ${requests} req${RESET}")
fi

# Lines added/removed
if [ "$(show_el lines)" = "1" ]; then
  segments+=("${DIM}📝${RESET} ${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}")
fi

# Claude process RAM
if [ "$(show_el claude_ram)" = "1" ] && [ "$claude_ram_mb" -gt 0 ]; then
  segments+=("${ram_color}mem: ${claude_ram_mb} MB${RESET}")
fi

# System RAM
if [ "$(show_el ram)" = "1" ] && [ "$ram_pct" -gt 0 ]; then
  segments+=("${DIM}ram${RESET} ${ram_color}${ram_bar} ${ram_used_gb}/${ram_total_gb}G${RESET}")
fi

# Join segments with separator (no trailing │)
out="\n\n"
first=1
for seg in "${segments[@]}"; do
  if [ "$first" = "1" ]; then
    out+="$seg"
    first=0
  else
    out+="${SEP}${seg}"
  fi
done

printf "%b" "$out"
