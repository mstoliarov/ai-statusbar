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

# ---------- Helper: build state.json with rate_limits ----------
write_state() {
  local s_pct=$1 s_rst=$2 w_pct=$3 w_rst=$4 s_fired=${5:-0} w_fired=${6:-0}
  "$JQ" -n \
    --argjson sp "$s_pct" --argjson sr "$s_rst" \
    --argjson wp "$w_pct" --argjson wr "$w_rst" \
    --argjson sf "$s_fired" --argjson wf "$w_fired" \
    '{tokens:{input:0,output:0},usage:{},requests_count:0,lines_count:0,
      rate_limits:{session:{pct:$sp,resets_at:$sr},weekly:{pct:$wp,resets_at:$wr}},
      autosave:{session_fired_for:$sf,weekly_fired_for:$wf}}' \
    > "$HOME/.ai-statusbar/state.json"
}

run_stop() {
  local stop_active=${1:-false}
  echo "{\"stop_hook_active\":$stop_active,\"model\":\"claude-opus-4-7\"}" \
    | bash "$STOP_HOOK"
}

# ---------- Test 2: session >= 95% triggers block ----------
echo "Test 2: session 96% triggers decision=block"
setup_fixture
write_state 96 111111 30 222222
OUT=$(run_stop false)
if echo "$OUT" | "$JQ" -e '.decision == "block"' >/dev/null 2>&1 \
   && echo "$OUT" | "$JQ" -r '.reason' | grep -qi "session 96%"; then
  pass "session trigger fires with correct reason"
else
  fail "expected decision=block with 'session 96%' in reason, got: $OUT"
fi
teardown_fixture

# ---------- Test 3: weekly >= 99% triggers block ----------
echo "Test 3: weekly 99% triggers decision=block"
setup_fixture
write_state 10 111111 99 222222
OUT=$(run_stop false)
if echo "$OUT" | "$JQ" -e '.decision == "block"' >/dev/null 2>&1 \
   && echo "$OUT" | "$JQ" -r '.reason' | grep -qi "weekly 99%"; then
  pass "weekly trigger fires with correct reason"
else
  fail "expected decision=block with 'weekly 99%' in reason, got: $OUT"
fi
teardown_fixture

# ---------- Test 4: already fired for this reset window → no block ----------
echo "Test 4: fired_for == resets_at → skip"
setup_fixture
write_state 96 111111 30 222222 111111 0
OUT=$(run_stop false)
if [ -z "$OUT" ] || ! echo "$OUT" | "$JQ" -e '.decision' >/dev/null 2>&1; then
  pass "skipped because already fired for this window"
else
  fail "expected empty stdout, got: $OUT"
fi
teardown_fixture

# ---------- Test 5: stop_hook_active=true → no block ----------
echo "Test 5: stop_hook_active=true → skip"
setup_fixture
write_state 96 111111 99 222222
OUT=$(run_stop true)
if [ -z "$OUT" ] || ! echo "$OUT" | "$JQ" -e '.decision' >/dev/null 2>&1; then
  pass "skipped because stop_hook_active is true"
else
  fail "expected empty stdout, got: $OUT"
fi
teardown_fixture

# ---------- Test 6: both thresholds reached → both mentioned in reason ----------
echo "Test 6: session 96% AND weekly 99% → both in reason"
setup_fixture
write_state 96 111111 99 222222
OUT=$(run_stop false)
if echo "$OUT" | "$JQ" -e '.decision == "block"' >/dev/null 2>&1 \
   && echo "$OUT" | "$JQ" -r '.reason' | grep -qi "session 96%" \
   && echo "$OUT" | "$JQ" -r '.reason' | grep -qi "weekly 99%"; then
  pass "both triggers mentioned"
else
  fail "expected both 'session 96%' and 'weekly 99%' in reason, got: $OUT"
fi
teardown_fixture

# ---------- Test 7: below thresholds → no block ----------
echo "Test 7: session 50%, weekly 50% → no block"
setup_fixture
write_state 50 111111 50 222222
OUT=$(run_stop false)
if [ -z "$OUT" ] || ! echo "$OUT" | "$JQ" -e '.decision' >/dev/null 2>&1; then
  pass "skipped because below thresholds"
else
  fail "expected empty stdout, got: $OUT"
fi
teardown_fixture

echo ""
echo "Summary: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
