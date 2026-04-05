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
LABEL="\033[0;37m"   # normal white — visible on dark AND light themes

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

# Format seconds as human duration: 7320 → "2h 2m", 90061 → "1d 1h"
fmt_duration() {
  local secs=$1
  [ "$secs" -le 0 ] && printf "now" && return
  local d=$(( secs / 86400 ))
  local h=$(( (secs % 86400) / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  if [ $d -gt 0 ]; then
    printf "%dd %dh" $d $h
  elif [ $h -gt 0 ]; then
    printf "%dh %dm" $h $m
  else
    printf "%dm" $m
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

# --- Parse all fields from statusLine JSON in one jq call ---
eval "$("$JQ" -r '
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "used_pct=\(.context_window.used_percentage // 0)",
  @sh "ctx_size=\(.context_window.context_window_size // 200000)",
  @sh "tok_in=\(.context_window.total_input_tokens // 0)",
  @sh "tok_out=\(.context_window.total_output_tokens // 0)",
  @sh "usage_5h=\(.rate_limits.five_hour.used_percentage // 0)",
  @sh "usage_7d=\(.rate_limits.seven_day.used_percentage // 0)",
  @sh "five_hour_resets_at=\(.rate_limits.five_hour.resets_at // 0)",
  @sh "seven_day_resets_at=\(.rate_limits.seven_day.resets_at // 0)",
  @sh "cost=\(.cost.total_cost_usd // 0)",
  @sh "lines_added=\(.cost.total_lines_added // 0)",
  @sh "lines_removed=\(.cost.total_lines_removed // 0)"
' <<< "$input")"

# --- Detect Extra Usage and API mode ---
# Extra Usage: context window expands to 1M tokens
is_extra_usage=0
[ "$ctx_size" -ge 1000000 ] && is_extra_usage=1

# API mode: rateLimitTier in credentials is not "default_claude_ai"
CREDS="$HOME/.claude/.credentials.json"
is_api_mode=0
if [ -f "$CREDS" ]; then
  rate_tier=$("$JQ" -r '.claudeAiOauth.rateLimitTier // "default_claude_ai"' "$CREDS" 2>/dev/null)
  [ "$rate_tier" != "default_claude_ai" ] && [ "$rate_tier" != "" ] && is_api_mode=1
fi

# --- Extra Usage credit balance (GET /api/oauth/usage, cached 1h, background refresh) ---
extra_balance_str=""
if [ "$is_extra_usage" = "1" ]; then
  USAGE_CACHE="$HOME/.ai-statusbar/.usage_cache"
  USAGE_CACHE_TTL=3600  # 1 hour — matches Claude Code internal cache (A9K=3600000ms)

  cache_age=999999
  if [ -f "$USAGE_CACHE" ]; then
    cache_age=$(( now_epoch - $(date -r "$USAGE_CACHE" +%s 2>/dev/null || stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0) ))
  fi

  if [ "$cache_age" -ge "$USAGE_CACHE_TTL" ]; then
    # Touch cache to prevent duplicate background fetches from parallel renders
    touch "$USAGE_CACHE" 2>/dev/null
    # Background fetch — never blocks the statusbar render
    (
      # Respect Retry-After: skip if still in backoff window
      RETRY_FILE="$HOME/.ai-statusbar/.usage_retry_after"
      if [ -f "$RETRY_FILE" ]; then
        retry_at=$(cat "$RETRY_FILE" 2>/dev/null)
        [ "$now_epoch" -lt "${retry_at:-0}" ] && exit
      fi

      _token=$("$JQ" -r '.claudeAiOauth.accessToken // ""' "$CREDS" 2>/dev/null)
      [ -z "$_token" ] && exit
      _ssl=""
      [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OS" == "Windows_NT" ]] && _ssl="--ssl-no-revoke"
      _ver=$(find /usr/local/lib /usr/lib "$HOME/AppData/Roaming/npm" -name "package.json" -path "*/claude-code/package.json" 2>/dev/null | head -1 | xargs "$JQ" -r '.version // ""' 2>/dev/null)
      _ver=${_ver:-2.1.92}
      _resp=$(curl -s $_ssl --max-time 5 -i \
        -H "Authorization: Bearer $_token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" \
        -H "User-Agent: claude-code/${_ver}; +https://support.anthropic.com/" \
        -H "x-service-name: claude-code" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
      # Extract Retry-After header and save backoff deadline
      retry_after=$(echo "$_resp" | grep -i "^Retry-After:" | awk '{print $2}' | tr -d '\r')
      if [ -n "$retry_after" ] && [ "$retry_after" -gt 0 ] 2>/dev/null; then
        echo $(( now_epoch + retry_after )) > "$RETRY_FILE"
        exit
      fi
      rm -f "$RETRY_FILE"
      # Strip HTTP headers, keep JSON body
      _body=$(echo "$_resp" | sed -n '/^{/,$ p' | head -1)
      # Only write cache on successful response (has extra_usage field)
      echo "$_body" | "$JQ" -e '.extra_usage' >/dev/null 2>&1 && echo "$_body" > "$USAGE_CACHE"
    ) &
  fi

  # Display from cache (stale-while-revalidate)
  if [ -f "$USAGE_CACHE" ] && [ "$(stat -c %s "$USAGE_CACHE" 2>/dev/null || stat -f %z "$USAGE_CACHE" 2>/dev/null || echo 0)" -gt 10 ]; then
    _used=$("$JQ" -r '.extra_usage.used_credits // 0' "$USAGE_CACHE" 2>/dev/null)
    _limit=$("$JQ" -r '.extra_usage.monthly_limit // 0' "$USAGE_CACHE" 2>/dev/null)
    if [ "$_limit" -gt 0 ] 2>/dev/null; then
      _used_fmt=$(awk "BEGIN {printf \"%.2f\", $_used/100}")
      _limit_fmt=$(awk "BEGIN {printf \"%.2f\", $_limit/100}")
      extra_balance_str="\$${_used_fmt}/\$${_limit_fmt}"
    fi
  fi
fi

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

# --- Derived values from parsed JSON ---
used_pct_int=$(printf "%.0f" "$used_pct")
ctx_color=$(pct_color "$used_pct_int")
ctx_bar=$(make_bar "$used_pct_int")
ctx_size_fmt=$(fmt_num "$ctx_size")

tok_total=$(( tok_in + tok_out ))
tok_in_fmt=$(fmt_num "$tok_in")
tok_out_fmt=$(fmt_num "$tok_out")

usage_5h_int=$(printf "%.0f" "$usage_5h")
usage_5h_bar=$(make_bar "$usage_5h_int")

usage_7d_int=$(printf "%.0f" "$usage_7d")
usage_7d_bar=$(make_bar "$usage_7d_int")

# --- State file (used for reset tracking and request counter) ---
STATE="$HOME/.ai-statusbar/state.json"

# --- Time until rate limit resets (resets_at is Unix epoch from statusLine JSON) ---
daily_reset_str=""
weekly_reset_str=""
now_epoch=$(date +%s)

if [ "$five_hour_resets_at" -gt 0 ] && [ "$usage_5h_int" -gt 0 ]; then
  secs_left=$(( five_hour_resets_at - now_epoch ))
  [ $secs_left -lt 0 ] && secs_left=0
  daily_reset_str=$(fmt_duration "$secs_left")
fi

if [ "$seven_day_resets_at" -gt 0 ]; then
  secs_left=$(( seven_day_resets_at - now_epoch ))
  [ $secs_left -lt 0 ] && secs_left=0
  weekly_reset_str=$(fmt_duration "$secs_left")
fi

cost_fmt=$(awk "BEGIN { printf \"%.2f\", $cost }")

# --- Request counter from state.json ---
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

# Folder + git
if [ "$(show_el workspace)" = "1" ]; then
  seg="${BOLD}${CYAN}${folder}${RESET}"
  if [ -n "$git_branch" ]; then
    seg+=" ${git_color}[${git_branch}${git_status_indicator}]${RESET}"
  fi
  segments+=("$seg")
fi

# Model
if [ -n "$model_short" ] && [ "$(show_el model)" = "1" ]; then
  segments+=("${MAGENTA}${model_short}${RESET}")
fi


# ctx — threshold colors; MAGENTA size when Extra Usage (ctx_size >= 1M)
if [ "$(show_el context)" = "1" ]; then
  if [ "$ctx_size" -ge 1000000 ]; then
    segments+=("${LABEL}ctx${RESET} ${ctx_color}${ctx_bar} ${used_pct_int}%${RESET} ${MAGENTA}/ ${ctx_size_fmt}${RESET}")
  else
    segments+=("${LABEL}ctx${RESET} ${ctx_color}${ctx_bar} ${used_pct_int}% / ${ctx_size_fmt}${RESET}")
  fi
fi

# extra_ctx — auto-shown when Extra Usage (overrides config); config controls non-Extra-Usage visibility
if [ "$is_extra_usage" = "1" ] || [ "$(show_el extra_ctx)" = "1" ]; then
  segments+=("${MAGENTA}extra ${ctx_size_fmt}${RESET}")
fi

# usage/d — 5h rate limit with optional reset time
if [ "$(show_el daily_limit)" = "1" ]; then
  seg="${LABEL}usage/d${RESET} ${BLUE}${usage_5h_bar} ${usage_5h_int}%${RESET}"
  if [ -n "$daily_reset_str" ]; then
    if [ "$daily_reset_approx" = "1" ]; then
      seg+=" ${DIM}(~${daily_reset_str})${RESET}"
    else
      seg+=" ${DIM}(${daily_reset_str})${RESET}"
    fi
  fi
  segments+=("$seg")
fi

# usage/w — 7d rate limit with optional reset time
if [ "$(show_el weekly_limit)" = "1" ]; then
  seg="${LABEL}usage/w${RESET} ${BLUE}${usage_7d_bar} ${usage_7d_int}%${RESET}"
  if [ -n "$weekly_reset_str" ]; then
    seg+=" ${DIM}(${weekly_reset_str})${RESET}"
  fi
  segments+=("$seg")
fi

# Token counter
if [ "$(show_el tokens)" = "1" ]; then
  segments+=("${LABEL}tok${RESET} ${GREEN}${tok_in_fmt}${RESET}${DIM}/${RESET}${RED}${tok_out_fmt}${RESET}")
fi

# Cost — auto-shown for Extra Usage and API mode (overrides config); config controls normal visibility
if [ "$is_extra_usage" = "1" ] || [ "$is_api_mode" = "1" ] || [ "$(show_el cost)" = "1" ]; then
  if [ -n "$extra_balance_str" ]; then
    # Extra Usage subscription: show credit balance (spent/total) in magenta
    segments+=("${MAGENTA}${extra_balance_str}${RESET}")
  else
    # Normal or API: show session cost
    segments+=("${LABEL}\$${cost_fmt}${RESET}")
  fi
fi

# Requests counter
if [ "$(show_el requests)" = "1" ]; then
  segments+=("${BLUE}🔧 ${requests} req${RESET}")
fi

# Lines added/removed
if [ "$(show_el lines)" = "1" ]; then
  segments+=("${LABEL}📝${RESET} ${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}")
fi

# Claude process RAM
if [ "$(show_el claude_ram)" = "1" ] && [ "$claude_ram_mb" -gt 0 ]; then
  segments+=("${ram_color}mem: ${claude_ram_mb} MB${RESET}")
fi

# System RAM
if [ "$(show_el ram)" = "1" ] && [ "$ram_pct" -gt 0 ]; then
  segments+=("${LABEL}ram${RESET} ${ram_color}${ram_bar} ${ram_used_gb}/${ram_total_gb}G${RESET}")
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
