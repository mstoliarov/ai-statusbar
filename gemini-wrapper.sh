#!/usr/bin/env bash
# Gemini CLI wrapper — source this in ~/.bashrc
# Usage: source ~/.ai-statusbar/gemini-wrapper.sh

gemini() {
  export PATH="$HOME/bin:$PATH"
  local JQ="$HOME/bin/jq"
  local STATE="$HOME/.ai-statusbar/state.json"

  # Initialize session state
  "$JQ" \
    --arg dir "$(pwd)" \
    --arg start "$(date -Iseconds)" \
    '.provider = "claude" |
     .provider = "gemini" |
     .session.project_dir = $dir |
     .session.start_iso = $start |
     .tool.name = "" |
     .tool.status = ""' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

  # Detect model from args (e.g. --model gemini-2.5-pro)
  local model=""
  local args=("$@")
  for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--model" || "${args[$i]}" == "-m" ]]; then
      model="${args[$((i+1))]}"
    fi
  done

  if [[ -n "$model" ]]; then
    "$JQ" --arg m "$model" '.model = $m' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  else
    "$JQ" '.model = "gemini"' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  fi

  # Run real gemini
  command gemini "$@"

  # Show status bar after completion
  bash "$HOME/.ai-statusbar/render.sh"
}
