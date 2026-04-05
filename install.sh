#!/usr/bin/env bash
# install.sh — one-command setup for ai-statusbar
# Run: bash ~/.ai-statusbar/install.sh

set -e

STATUSBAR_DIR="$HOME/.ai-statusbar"
BIN_DIR="$HOME/bin"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
BASHRC="$HOME/.bashrc"

echo "==> Installing ai-statusbar..."

# Detect platform
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OS" == "Windows_NT" ]]; then
  PLATFORM="windows"
else
  PLATFORM="linux"
fi
echo "    Platform: $PLATFORM"

# 1. Create directories
mkdir -p "$STATUSBAR_DIR/hooks" "$BIN_DIR"

# 2. Install jq if missing
if ! "$BIN_DIR/jq" --version &>/dev/null 2>&1 && ! "$BIN_DIR/jq.exe" --version &>/dev/null 2>&1; then
  echo "==> Downloading jq..."
  if [[ "$PLATFORM" == "windows" ]]; then
    curl -sL --ssl-no-revoke \
      "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe" \
      -o "$BIN_DIR/jq.exe"
  else
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && JQ_ARCH="arm64" || JQ_ARCH="amd64"
    curl -sL \
      "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}" \
      -o "$BIN_DIR/jq"
    chmod +x "$BIN_DIR/jq"
  fi
  echo "    jq installed"
else
  echo "    jq already present"
fi

# Resolve jq binary path
JQ="$BIN_DIR/jq"
[[ -f "$BIN_DIR/jq.exe" && ! -f "$BIN_DIR/jq" ]] && JQ="$BIN_DIR/jq.exe"

# 3. Add ~/bin to PATH in .bashrc if not already there
if ! grep -q '$HOME/bin' "$BASHRC" 2>/dev/null; then
  echo '' >> "$BASHRC"
  echo '# ai-statusbar tools' >> "$BASHRC"
  echo 'export PATH="$HOME/bin:$PATH"' >> "$BASHRC"
  echo "    Added ~/bin to PATH in .bashrc"
fi

# 5. Patch Claude Code settings.json with hooks
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo '{}' > "$CLAUDE_SETTINGS"
fi

CURRENT=$(<"$CLAUDE_SETTINGS")

if echo "$CURRENT" | "$JQ" -e '.hooks.PostToolUse' &>/dev/null && \
   echo "$CURRENT" | "$JQ" -e '.hooks.Stop' &>/dev/null; then
  echo "    Claude Code hooks already configured"
else
  echo "$CURRENT" | "$JQ" '
    .hooks.PostToolUse = [{"matcher": "", "hooks": [{"type": "command", "command": "bash ~/.ai-statusbar/hooks/post-tool.sh"}]}] |
    .hooks.Stop = [{"matcher": "", "hooks": [{"type": "command", "command": "bash ~/.ai-statusbar/hooks/stop.sh"}]}]
  ' > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
  echo "    Claude Code hooks added to settings.json"
fi

# 6. Configure Claude Code statusLine
CURRENT=$(<"$CLAUDE_SETTINGS")
if echo "$CURRENT" | "$JQ" -e '.statusLine' &>/dev/null; then
  echo "    statusLine already configured"
else
  echo "$CURRENT" | "$JQ" \
    '.statusLine = {"type": "command", "command": "bash ~/.ai-statusbar/statusline.sh"}' \
    > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
  echo "    statusLine configured"
fi

# 7. Register /statusbar slash command in ~/.claude/commands/
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$CLAUDE_COMMANDS_DIR"
COMMAND_TARGET="$CLAUDE_COMMANDS_DIR/statusbar.md"
if [[ ! -e "$COMMAND_TARGET" ]]; then
  ln -sf "$STATUSBAR_DIR/commands/statusbar.md" "$COMMAND_TARGET"
  echo "    /statusbar command registered"
else
  echo "    /statusbar command already registered"
fi

# 8. Initialize default config if not present
CONFIG="$STATUSBAR_DIR/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo '{"show":{"workspace":true,"model":true,"context":true,"tokens":true,"cost":true,"daily_limit":true,"weekly_limit":true,"requests":true,"lines":true,"claude_ram":true,"ram":true}}' \
    | "$JQ" '.' > "$CONFIG"
  echo "    Default config.json created (all elements enabled)"
else
  echo "    config.json already present"
fi

echo ""
echo "==> Done! ai-statusbar installed."
echo ""
echo "    Reload:    source ~/.bashrc"
echo "    Config:    type /statusbar in Claude Code"
echo ""
echo "    The status bar will appear automatically in Claude Code."
