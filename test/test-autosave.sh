#!/usr/bin/env bash
# Regression tests for AutoSave usage-limits feature.
# Run from source repo root.

set -u
export PATH="$HOME/bin:$PATH"
JQ="$HOME/bin/jq"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATUSLINE="$SRC_DIR/statusline.sh"
STOP_HOOK="$SRC_DIR/hooks/stop.sh"

# Fixture: temporary HOME with fake .ai-statusbar
setup_fixture() {
  FIXTURE_HOME=$(mktemp -d)
  mkdir -p "$FIXTURE_HOME/.ai-statusbar/hooks" "$FIXTURE_HOME/bin"
  # jq must be reachable via $FIXTURE_HOME/bin
  ln -sf "$JQ" "$FIXTURE_HOME/bin/jq" 2>/dev/null || cp "$JQ" "$FIXTURE_HOME/bin/jq"
  # Minimal state.json
  echo '{"tokens":{"input":0,"output":0},"usage":{},"requests_count":0,"lines_count":0}' \
    > "$FIXTURE_HOME/.ai-statusbar/state.json"
  export HOME="$FIXTURE_HOME"
}

teardown_fixture() {
  rm -rf "$FIXTURE_HOME"
}

PASSED=0; FAILED=0
pass() { PASSED=$((PASSED+1)); echo "  [OK] $1"; }
fail() { FAILED=$((FAILED+1)); echo "  [FAIL] $1"; }

# ---------- Test 1: statusline dumps rate_limits to state.json ----------
echo "Test 1: statusline.sh writes rate_limits to state.json"
setup_fixture
INPUT='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":100,"total_output_tokens":50},"rate_limits":{"five_hour":{"used_percentage":87,"resets_at":1745089200},"seven_day":{"used_percentage":42,"resets_at":1745520000}}}'
echo "$INPUT" | bash "$STATUSLINE" >/dev/null 2>&1

S_PCT=$("$JQ" -r '.rate_limits.session.pct // "missing"' "$HOME/.ai-statusbar/state.json")
W_PCT=$("$JQ" -r '.rate_limits.weekly.pct // "missing"' "$HOME/.ai-statusbar/state.json")
S_RST=$("$JQ" -r '.rate_limits.session.resets_at // "missing"' "$HOME/.ai-statusbar/state.json")
W_RST=$("$JQ" -r '.rate_limits.weekly.resets_at // "missing"' "$HOME/.ai-statusbar/state.json")

if [ "$S_PCT" = "87" ] && [ "$W_PCT" = "42" ] && [ "$S_RST" = "1745089200" ] && [ "$W_RST" = "1745520000" ]; then
  pass "rate_limits written correctly (S=$S_PCT% W=$W_PCT%)"
else
  fail "expected S=87 W=42 R5=1745089200 R7=1745520000, got S=$S_PCT W=$W_PCT R5=$S_RST R7=$W_RST"
fi
teardown_fixture

echo ""
echo "Summary: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
