#!/usr/bin/env bash
# install.sh — one-command setup for ai-statusbar
# Run: bash ~/.ai-statusbar/install.sh

set -e

STATUSBAR_DIR="$HOME/.ai-statusbar"
BIN_DIR="$HOME/bin"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
BASHRC="$HOME/.bashrc"

echo "==> Installing ai-statusbar..."

# 1. Create directories
mkdir -p "$STATUSBAR_DIR/hooks" "$BIN_DIR"

# 2. Install jq if missing
if ! "$BIN_DIR/jq" --version &>/dev/null; then
  echo "==> Downloading jq..."
  curl -sL --ssl-no-revoke \
    "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe" \
    -o "$BIN_DIR/jq.exe"
  echo "    jq installed"
else
  echo "    jq already present"
fi

# Use jq alias for cross-platform (git bash on Windows uses .exe)
JQ="$BIN_DIR/jq"
[[ -f "$BIN_DIR/jq.exe" && ! -f "$BIN_DIR/jq" ]] && JQ="$BIN_DIR/jq.exe"

# 3. Install gum if missing
if ! "$BIN_DIR/gum" --version &>/dev/null 2>&1 && ! "$BIN_DIR/gum.exe" --version &>/dev/null 2>&1; then
  echo "==> Downloading gum..."
  curl -sL --ssl-no-revoke \
    "https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_Windows_x86_64.zip" \
    -o /tmp/gum.zip
  mkdir -p /tmp/gum_extract
  unzip -o /tmp/gum.zip -d /tmp/gum_extract
  cp /tmp/gum_extract/gum_0.14.5_Windows_x86_64/gum.exe "$BIN_DIR/gum.exe"
  rm -rf /tmp/gum.zip /tmp/gum_extract
  echo "    gum installed"
else
  echo "    gum already present"
fi

# 4. Add ~/bin to PATH in .bashrc if not already there
if ! grep -q 'ai-statusbar.*PATH\|PATH.*bin.*ai-status\|HOME.*bin.*PATH' "$BASHRC" 2>/dev/null; then
  if ! grep -q '"$HOME/bin"' "$BASHRC" 2>/dev/null && ! grep -q '$HOME/bin:' "$BASHRC" 2>/dev/null; then
    echo '' >> "$BASHRC"
    echo '# ai-statusbar tools' >> "$BASHRC"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$BASHRC"
    echo "    Added ~/bin to PATH in .bashrc"
  fi
fi

# 5. Add Gemini wrapper to .bashrc
if ! grep -q 'ai-statusbar/gemini-wrapper' "$BASHRC" 2>/dev/null; then
  echo '' >> "$BASHRC"
  echo '# Gemini CLI status bar wrapper' >> "$BASHRC"
  echo 'source "$HOME/.ai-statusbar/gemini-wrapper.sh"' >> "$BASHRC"
  echo "    Added Gemini wrapper to .bashrc"
else
  echo "    Gemini wrapper already in .bashrc"
fi

# 6. Patch Claude Code settings.json with hooks
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo '{}' > "$CLAUDE_SETTINGS"
fi

CURRENT=$(<"$CLAUDE_SETTINGS")

# Check if hooks already present
if echo "$CURRENT" | "$JQ" -e '.hooks.PostToolUse' &>/dev/null && \
   echo "$CURRENT" | "$JQ" -e '.hooks.Stop' &>/dev/null; then
  echo "    Claude Code hooks already configured"
else
  echo "$CURRENT" | "$JQ" '
    .hooks.PostToolUse = [{"command": "bash ~/.ai-statusbar/hooks/post-tool.sh"}] |
    .hooks.Stop = [{"command": "bash ~/.ai-statusbar/hooks/stop.sh"}]
  ' > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
  echo "    Claude Code hooks added to settings.json"
fi

# 7. Configure Claude Code statusLine
CURRENT=$(<"$CLAUDE_SETTINGS")
if echo "$CURRENT" | "$JQ" -e '.statusLine' &>/dev/null; then
  echo "    statusLine already configured"
else
  echo "$CURRENT" | "$JQ" \
    '.statusLine = {"type": "command", "command": "bash ~/.ai-statusbar/statusline.sh"}' \
    > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
  echo "    statusLine configured"
fi

# 8. Initialize default config if not present
CONFIG="$STATUSBAR_DIR/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo '{"show":{"model":true,"auth":true,"context":true,"daily_limit":true,"weekly_limit":true,"tokens":true,"cost":true,"requests":true,"lines":true}}' \
    | "$JQ" '.' > "$CONFIG"
  echo "    Default config.json created (all elements enabled)"
else
  echo "    config.json already present"
fi

echo ""
echo "==> Done! ai-statusbar installed."
echo ""
echo "    Test:      bash ~/.ai-statusbar/render.sh"
echo "    Reload:    source ~/.bashrc"
echo "    Configure: bash ~/.ai-statusbar/configure.sh"
echo "               (or type /statusbar in Claude Code)"
echo ""
echo "    The status bar will appear automatically after each Claude/Gemini response."
