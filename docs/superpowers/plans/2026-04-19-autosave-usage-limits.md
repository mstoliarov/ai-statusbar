# AutoSave Usage Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Автоматический триггер `/saveplan` + `/closeday` при session ≥95% или weekly ≥99% rate limits.

**Architecture:** Встраиваем в существующие `ai-statusbar/statusline.sh` и `ai-statusbar/hooks/stop.sh` — ноль новых production-скриптов. StatusLine пишет rate_limits в `state.json`, Stop hook читает и при пороге возвращает `decision:block`. Anti-loop через `fired_for == resets_at`.

**Tech Stack:** bash, jq (уже установлен в `~/bin/jq`), существующий `state.json` как обменник.

**Репозиторий:** `~/OneDrive/.PROJECTS/ai-statusbar/` (git source).
**Deploy:** `~/.ai-statusbar/` (куда смотрит Claude Code settings.json).

**Важно:** после каждой правки source-файла нужно синхронизировать deploy простым `cp`, иначе Claude Code продолжит использовать старую версию.

---

## Baseline sync

Перед началом работы: deploy `hooks/stop.sh` отстаёт от source. Синхронизируем, чтобы стартовать с одинаковой базой.

### Task 0: Sync deploy baseline

**Files:**
- Modify: `~/.ai-statusbar/hooks/stop.sh` (копия из source)

- [ ] **Step 1: Copy current source to deploy**

```bash
cp ~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh ~/.ai-statusbar/hooks/stop.sh
```

- [ ] **Step 2: Verify no diff remains**

```bash
diff -q ~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh ~/.ai-statusbar/hooks/stop.sh
```

Expected: no output (files identical).

- [ ] **Step 3: Verify deploy runs without errors**

```bash
echo '{"model":"claude-opus-4-7"}' | bash ~/.ai-statusbar/hooks/stop.sh
echo "exit=$?"
```

Expected: `exit=0`, no stderr.

No commit — deploy is not under git.

---

## Feature: rate_limits dump в state.json

### Task 1: Write failing test for rate_limits dump

**Files:**
- Create: `~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh`

- [ ] **Step 1: Create test harness with first test case**

```bash
cat > ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh <<'EOF'
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
EOF
chmod +x ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

- [ ] **Step 2: Run test — should FAIL**

```bash
bash ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

Expected output contains:
```
[FAIL] expected S=87 W=42 R5=1745089200 R7=1745520000, got S=missing ...
Summary: 0 passed, 1 failed
```

(statusline.sh ещё не пишет rate_limits в state.json)

### Task 2: Implement rate_limits dump in statusline.sh

**Files:**
- Modify: `~/OneDrive/.PROJECTS/ai-statusbar/statusline.sh` (после блока сохранения токенов, ~строка 339)

- [ ] **Step 1: Add rate_limits dump block**

Найти в source `statusline.sh` блок:
```bash
# Save live token counts to state.json for stop.sh daily/weekly accumulation
if [ "$tok_total" -gt 0 ] && [ -f "$STATE" ]; then
  "$JQ" --argjson ti "$tok_in" --argjson to "$tok_out" \
    '.tokens.input = $ti | .tokens.output = $to' \
    "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
fi
```

Сразу после него (перед `# --- Build output ---`) вставить:

```bash
# Save rate_limits snapshot for stop.sh autosave trigger
if [ -f "$STATE" ]; then
  "$JQ" --argjson sp "$usage_5h_int" --argjson sr "$five_hour_resets_at" \
        --argjson wp "$usage_7d_int" --argjson wr "$seven_day_resets_at" \
        '.rate_limits.session = {pct: $sp, resets_at: $sr} |
         .rate_limits.weekly  = {pct: $wp, resets_at: $wr}' \
        "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
fi
```

- [ ] **Step 2: Run test — should PASS**

```bash
bash ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

Expected:
```
  [OK] rate_limits written correctly (S=87% W=42%)
Summary: 1 passed, 0 failed
```

- [ ] **Step 3: Sync deploy**

```bash
cp ~/OneDrive/.PROJECTS/ai-statusbar/statusline.sh ~/.ai-statusbar/statusline.sh
```

- [ ] **Step 4: Commit**

```bash
cd ~/OneDrive/.PROJECTS/ai-statusbar
git add statusline.sh test/test-autosave.sh
git commit -m "feat: dump rate_limits to state.json for autosave trigger"
```

---

## Feature: autosave trigger в stop.sh

### Task 3: Extend test harness with stop.sh trigger cases

**Files:**
- Modify: `~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh`

- [ ] **Step 1: Append 5 new test cases before Summary line**

Открыть `test/test-autosave.sh`, найти строку `echo "Summary: $PASSED passed, $FAILED failed"` и **перед ней** вставить:

```bash
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
write_state 96 111111 30 222222 111111 0   # session_fired_for=111111 matches resets_at
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
```

- [ ] **Step 2: Run extended test — Tests 2-7 should FAIL**

```bash
bash ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

Expected:
```
  [OK] rate_limits written correctly (S=87% W=42%)
  [FAIL] expected decision=block with 'session 96%' in reason, got: ...
  [FAIL] expected decision=block with 'weekly 99%' in reason, got: ...
  [OK] skipped because already fired for this window
  [OK] skipped because stop_hook_active is true
  [FAIL] expected both 'session 96%' and 'weekly 99%' in reason, got: ...
  [OK] skipped because below thresholds
Summary: 4 passed, 3 failed
```

Note: tests 4, 5, 7 pass because stop.sh без autosave-логики всегда выходит тихо (decision никогда не пишется). Это ложный pass — но после имплементации настоящие проверки останутся валидными. Tests 2, 3, 6 реально падают из-за отсутствия autosave-ветки.

### Task 4: Implement autosave trigger in hooks/stop.sh

**Files:**
- Modify: `~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh`

- [ ] **Step 1: Insert autosave block after TOTAL_TOKENS computation**

Найти в `hooks/stop.sh` строку:
```bash
TOTAL_TOKENS=$(( TOKENS_IN + TOKENS_OUT ))
```

Сразу после неё (перед `# Dynamic pricing by model`) вставить:

```bash
# --- AutoSave trigger: session ≥95% OR weekly ≥99% ---
STOP_HOOK_ACTIVE=$(echo "$INPUT" | "$JQ" -r '.stop_hook_active // false')

if [[ "$STOP_HOOK_ACTIVE" != "true" && -f "$STATE" ]]; then
  S_PCT=$("$JQ" -r '.rate_limits.session.pct // 0' "$STATE")
  W_PCT=$("$JQ" -r '.rate_limits.weekly.pct // 0' "$STATE")
  S_RESET=$("$JQ" -r '.rate_limits.session.resets_at // 0' "$STATE")
  W_RESET=$("$JQ" -r '.rate_limits.weekly.resets_at // 0' "$STATE")
  S_FIRED=$("$JQ" -r '.autosave.session_fired_for // 0' "$STATE")
  W_FIRED=$("$JQ" -r '.autosave.weekly_fired_for // 0' "$STATE")

  REASONS=()
  if [ "${S_PCT:-0}" -ge 95 ] && [ "$S_FIRED" != "$S_RESET" ]; then
    REASONS+=("session ${S_PCT}%")
    "$JQ" --argjson r "$S_RESET" '.autosave.session_fired_for = $r' \
      "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  fi
  if [ "${W_PCT:-0}" -ge 99 ] && [ "$W_FIRED" != "$W_RESET" ]; then
    REASONS+=("weekly ${W_PCT}%")
    "$JQ" --argjson r "$W_RESET" '.autosave.weekly_fired_for = $r' \
      "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  fi

  if [ "${#REASONS[@]}" -gt 0 ]; then
    REASON_TXT="AutoSave: порог достигнут ($(IFS=', '; echo "${REASONS[*]}")). Выполни /saveplan, затем /closeday, затем заверши."
    "$JQ" -n --arg r "$REASON_TXT" '{decision:"block", reason:$r}'
    exit 0
  fi
fi
# --- end AutoSave ---
```

- [ ] **Step 2: Run test — all 7 should PASS**

```bash
bash ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

Expected:
```
  [OK] rate_limits written correctly (S=87% W=42%)
  [OK] session trigger fires with correct reason
  [OK] weekly trigger fires with correct reason
  [OK] skipped because already fired for this window
  [OK] skipped because stop_hook_active is true
  [OK] both triggers mentioned
  [OK] skipped because below thresholds
Summary: 7 passed, 0 failed
```

- [ ] **Step 3: Sync deploy**

```bash
cp ~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh ~/.ai-statusbar/hooks/stop.sh
```

- [ ] **Step 4: Commit**

```bash
cd ~/OneDrive/.PROJECTS/ai-statusbar
git add hooks/stop.sh test/test-autosave.sh
git commit -m "feat: autosave trigger on session/weekly usage thresholds"
```

---

## Hook wiring

### Task 5: Update ~/.claude/settings.json

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Show current hooks block**

```bash
jq '.hooks' ~/.claude/settings.json
```

Expected (pre-change):
```json
{
  "PostToolUse": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/OneDrive/.PROJECTS/ai-statusbar/hooks/post-tool.sh"
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Replace hooks block (fix PostToolUse path + add Stop)**

```bash
jq '.hooks = {
  "PostToolUse": [
    {"matcher": "", "hooks": [{"type": "command", "command": "bash ~/.ai-statusbar/hooks/post-tool.sh"}]}
  ],
  "Stop": [
    {"matcher": "", "hooks": [{"type": "command", "command": "bash ~/.ai-statusbar/hooks/stop.sh"}]}
  ]
}' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

- [ ] **Step 3: Verify result**

```bash
jq '.hooks' ~/.claude/settings.json
```

Expected:
```json
{
  "PostToolUse": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.ai-statusbar/hooks/post-tool.sh"
        }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.ai-statusbar/hooks/stop.sh"
        }
      ]
    }
  ]
}
```

- [ ] **Step 4: Verify settings.json still valid JSON**

```bash
jq -e . ~/.claude/settings.json >/dev/null && echo "valid JSON"
```

Expected: `valid JSON`

No commit — `~/.claude/settings.json` is not under git.

---

## Smoke test в живой системе

### Task 6: End-to-end smoke test

**Files:** (read-only checks)

- [ ] **Step 1: Verify deploy matches source**

```bash
diff -q ~/OneDrive/.PROJECTS/ai-statusbar/statusline.sh ~/.ai-statusbar/statusline.sh
diff -q ~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh ~/.ai-statusbar/hooks/stop.sh
diff -q ~/OneDrive/.PROJECTS/ai-statusbar/hooks/post-tool.sh ~/.ai-statusbar/hooks/post-tool.sh
```

Expected: all three commands produce no output.

- [ ] **Step 2: Backup real state.json**

```bash
cp ~/.ai-statusbar/state.json ~/.ai-statusbar/state.json.bak
```

- [ ] **Step 3: Force state.json into trigger condition**

```bash
jq '.rate_limits = {session:{pct:96,resets_at:111111},weekly:{pct:30,resets_at:222222}} | .autosave = {}' \
  ~/.ai-statusbar/state.json > ~/.ai-statusbar/state.json.tmp \
  && mv ~/.ai-statusbar/state.json.tmp ~/.ai-statusbar/state.json
```

- [ ] **Step 4: Manually invoke stop.sh as Claude Code would**

```bash
echo '{"session_id":"smoke","transcript_path":"/tmp/t","stop_hook_active":false,"model":"claude-opus-4-7"}' \
  | bash ~/.ai-statusbar/hooks/stop.sh
```

Expected stdout (example):
```json
{"decision":"block","reason":"AutoSave: порог достигнут (session 96%). Выполни /saveplan, затем /closeday, затем заверши."}
```

- [ ] **Step 5: Verify fired_for was set**

```bash
jq '.autosave' ~/.ai-statusbar/state.json
```

Expected:
```json
{"session_fired_for": 111111}
```

- [ ] **Step 6: Second invocation should be silent (fired_for matches)**

```bash
echo '{"session_id":"smoke","transcript_path":"/tmp/t","stop_hook_active":false,"model":"claude-opus-4-7"}' \
  | bash ~/.ai-statusbar/hooks/stop.sh
```

Expected stdout: empty (no decision output; hook proceeds to normal state write).

- [ ] **Step 7: Restore real state.json**

```bash
mv ~/.ai-statusbar/state.json.bak ~/.ai-statusbar/state.json
```

- [ ] **Step 8: Verify restored**

```bash
jq '.tokens' ~/.ai-statusbar/state.json
```

Expected: `{"input": ..., "output": ..., ...}` (real token counts, not zero-fixture).

No commit.

---

## Финал

### Task 7: Commit README update

**Files:**
- Modify: `~/OneDrive/.PROJECTS/ai-statusbar/README.md`

- [ ] **Step 1: Append AutoSave section**

Найти последний раздел README.md, добавить в конец (перед EOF):

```markdown

## AutoSave on usage limits

Stop hook автоматически триггерит сохранение, когда:
- **session ≥ 95%** (5-часовое окно), или
- **weekly ≥ 99%**

При срабатывании Claude получает инструкцию выполнить `/saveplan` и `/closeday`, затем завершается. Anti-loop: один выстрел на окно через `autosave.session_fired_for == rate_limits.session.resets_at`.

Пороги зашиты в `hooks/stop.sh` (константы 95 и 99). Регрессия покрыта `test/test-autosave.sh`.
```

- [ ] **Step 2: Commit**

```bash
cd ~/OneDrive/.PROJECTS/ai-statusbar
git add README.md
git commit -m "docs: describe AutoSave trigger in README"
```

- [ ] **Step 3: Verify all tests still pass**

```bash
bash ~/OneDrive/.PROJECTS/ai-statusbar/test/test-autosave.sh
```

Expected: `Summary: 7 passed, 0 failed`

- [ ] **Step 4: Final git log check**

```bash
cd ~/OneDrive/.PROJECTS/ai-statusbar && git log --oneline -5
```

Expected: 4 new commits on top of `8aa80f3 docs: spec AutoSave...`:
1. `docs: describe AutoSave trigger in README`
2. `feat: autosave trigger on session/weekly usage thresholds`
3. `feat: dump rate_limits to state.json for autosave trigger`
4. `8aa80f3 docs: spec AutoSave при приближении usage limits`

---

## Verification checklist

После всех задач:

- [ ] `test/test-autosave.sh` → 7/7 pass
- [ ] `~/OneDrive/.PROJECTS/ai-statusbar/statusline.sh` идентичен `~/.ai-statusbar/statusline.sh`
- [ ] `~/OneDrive/.PROJECTS/ai-statusbar/hooks/stop.sh` идентичен `~/.ai-statusbar/hooks/stop.sh`
- [ ] `~/.claude/settings.json` содержит `.hooks.Stop` и обновлённый путь `PostToolUse`
- [ ] Smoke test (Task 6) отработал с `decision:block` при pct=96
- [ ] Реальный `state.json` восстановлен
- [ ] Git-дерево чистое, все правки закоммичены
