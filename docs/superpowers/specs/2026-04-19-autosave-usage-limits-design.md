# AutoSave при приближении Usage Limits

**Дата:** 2026-04-19
**Фича:** автоматический триггер `/saveplan` + `/closeday` при достижении порогов Claude Code rate limits.

## Цель

Не потерять состояние сессии при принудительном отключении по лимиту. Когда session (5-часовое окно) ≥ 95% или weekly ≥ 99%, Claude должен успеть сохранить план проекта и журнал сессии, пока остаётся небольшой token-запас.

## Источник данных

Claude Code нативно передаёт в stdin statusLine-скрипта:

```json
{
  "rate_limits": {
    "five_hour": {"used_percentage": 87, "resets_at": 1745089200},
    "seven_day": {"used_percentage": 42, "resets_at": 1745520000}
  }
}
```

Stop hook эти поля **не** получает — у него в stdin только `session_id`, `transcript_path`, `stop_hook_active`. Поэтому statusLine действует как сборщик, state.json — как обменник.

## Архитектура

Полностью встроено в существующий `ai-statusbar` — ноль новых файлов.

```
~/OneDrive/.PROJECTS/ai-statusbar/           (git source)
├── statusline.sh          # +5 строк: dump rate_limits в state.json
├── hooks/stop.sh          # +30 строк: autosave-ветка перед финальным write
└── install.sh             # без изменений (уже подключает Stop hook)

~/.ai-statusbar/            (deploy, куда смотрит settings.json)
├── statusline.sh          # копия source
├── hooks/stop.sh          # копия source
└── state.json             # runtime обменник

~/.claude/settings.json     # подключить Stop, перевести PostToolUse на deploy-путь
```

## Поток данных

1. Claude Code ~100 мс вызывает statusLine → `statusline.sh` парсит `rate_limits` (уже делает) и дополнительно пишет в `state.json`:
   ```json
   "rate_limits": {
     "session": {"pct": 87, "resets_at": 1745089200},
     "weekly":  {"pct": 42, "resets_at": 1745520000}
   }
   ```
2. Claude заканчивает тур → harness дёргает Stop hook → `stop.sh`.
3. `stop.sh` (уже читает `state.json` для tokens) дочитывает `rate_limits` и проверяет триггер.
4. Если порог достигнут и ещё не стреляли для текущего `resets_at` и `stop_hook_active != true`:
   - Обновляет `.autosave.{session,weekly}_fired_for = resets_at` в `state.json`.
   - Печатает в stdout: `{"decision":"block","reason":"AutoSave порог достигнут (session NN% / weekly NN%). Выполни /saveplan, затем /closeday, затем заверши."}`.
   - `exit 0`.
5. Harness видит `block` → возвращает управление Claude с reason в контексте. Claude выполняет оба сохранения и снова останавливается.
6. На повторном Stop: `fired_for == resets_at` → триггер пропускается → обычный exit → сессия спокойно завершается.
7. При резете окна `resets_at` меняется → `fired_for` автоматически устаревает → следующий триггер в новом окне отработает.

## Компоненты

### statusline.sh (правка)

После блока `Save live token counts to state.json` (~ строка 335 в source) добавить:

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

Никаких сетевых вызовов, ни новых зависимостей.

### hooks/stop.sh (правка)

После строки 27 (`TOTAL_TOKENS=...`) и до существующего блока обновления state.json — вставить autosave-ветку:

```bash
# --- AutoSave trigger ---
STOP_HOOK_ACTIVE=$(echo "$INPUT" | "$JQ" -r '.stop_hook_active // false')

if [[ "$STOP_HOOK_ACTIVE" != "true" && -f "$STATE" ]]; then
  S_PCT=$("$JQ" -r '.rate_limits.session.pct // 0' "$STATE")
  W_PCT=$("$JQ" -r '.rate_limits.weekly.pct // 0' "$STATE")
  S_RESET=$("$JQ" -r '.rate_limits.session.resets_at // 0' "$STATE")
  W_RESET=$("$JQ" -r '.rate_limits.weekly.resets_at // 0' "$STATE")
  S_FIRED=$("$JQ" -r '.autosave.session_fired_for // 0' "$STATE")
  W_FIRED=$("$JQ" -r '.autosave.weekly_fired_for // 0' "$STATE")

  TRIGGER=0
  REASONS=()
  if [ "$S_PCT" -ge 95 ] && [ "$S_FIRED" != "$S_RESET" ]; then
    TRIGGER=1
    REASONS+=("session ${S_PCT}%")
    "$JQ" --argjson r "$S_RESET" '.autosave.session_fired_for = $r' \
      "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  fi
  if [ "$W_PCT" -ge 99 ] && [ "$W_FIRED" != "$W_RESET" ]; then
    TRIGGER=1
    REASONS+=("weekly ${W_PCT}%")
    "$JQ" --argjson r "$W_RESET" '.autosave.weekly_fired_for = $r' \
      "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
  fi

  if [ "$TRIGGER" = "1" ]; then
    REASON_TXT="AutoSave: порог достигнут ($(IFS=', '; echo "${REASONS[*]}")). Выполни /saveplan, затем /closeday, затем заверши."
    "$JQ" -n --arg r "$REASON_TXT" '{decision:"block", reason:$r}'
    exit 0
  fi
fi
# --- end AutoSave ---
```

Существующий блок обновления токенов/usage в state.json остаётся без изменений — выполнится если триггер не сработал.

### settings.json (правка)

```diff
   "hooks": {
     "PostToolUse": [
       {
         "matcher": "",
         "hooks": [
           {
             "type": "command",
-            "command": "bash ~/OneDrive/.PROJECTS/ai-statusbar/hooks/post-tool.sh"
+            "command": "bash ~/.ai-statusbar/hooks/post-tool.sh"
           }
         ]
       }
+    ],
+    "Stop": [
+      {
+        "matcher": "",
+        "hooks": [
+          {
+            "type": "command",
+            "command": "bash ~/.ai-statusbar/hooks/stop.sh"
+          }
+        ]
+      }
     ]
   }
```

### Sync deploy

После правок source:
```bash
cp ~/OneDrive/.PROJECTS/ai-statusbar/statusline.sh ~/.ai-statusbar/
cp ~/OneDrive/.PROJECTS/ai-statusbar/hooks/*.sh ~/.ai-statusbar/hooks/
```

## Anti-loop механизм

Три защиты (достаточно любой одной, но используем все):
1. **`stop_hook_active` флаг** — harness выставляет, если Stop уже форсил продолжение. Мы проверяем в самом начале и выходим без действий.
2. **`fired_for == resets_at`** — один выстрел на окно. При резете окна `resets_at` меняется → метка автоустаревает.
3. **Claude после выполнения `/saveplan` + `/closeday`** делает обычный Stop; метка уже стоит → второй block не триггерится.

## Обработка ошибок

- `state.json` отсутствует/битый → autosave тихо пропускается (условие `-f "$STATE"`). StatusLine создаст его позже.
- `rate_limits` отсутствует в JSON → `jq` вернёт 0, триггер не сработает (95/99 > 0).
- Отрицательные/невалидные `resets_at` → не ломают логику: сравнение строк всё равно даст несовпадение → триггер сработает в текущем окне, в следующем — снова.
- Claude не выполнил `/saveplan`/`/closeday` (например, сразу упёрся в лимит): метка `fired_for` уже выставлена → повторных попыток не будет. Это осознанный trade-off: лучше один неудачный автосейв, чем цикл.

## Тестирование

Ручные проверки перед коммитом:

1. **Trigger fires:**
   ```bash
   jq '.rate_limits={session:{pct:96,resets_at:999},weekly:{pct:30,resets_at:888}} | .autosave={}' ~/.ai-statusbar/state.json > /tmp/s.json && mv /tmp/s.json ~/.ai-statusbar/state.json
   echo '{"stop_hook_active":false,"model":"claude-opus-4-7"}' | bash ~/.ai-statusbar/hooks/stop.sh
   ```
   Ожидание: stdout содержит `{"decision":"block","reason":"AutoSave: порог достигнут (session 96%) ..."}`.

2. **Second call skipped (fired_for set):**
   Тот же state.json (уже с `autosave.session_fired_for=999`) → повторный вызов → stdout пустой, блок не сработал.

3. **stop_hook_active guard:**
   `echo '{"stop_hook_active":true,...}'` → пустой stdout.

4. **Weekly trigger:**
   `session:{pct:10}, weekly:{pct:99}` → reason содержит `weekly 99%`.

5. **Both trigger at once:**
   `session:{pct:96}, weekly:{pct:99}` с разными `resets_at` → reason содержит оба.

6. **Integration smoke:**
   Запустить Claude с settings.json, открыть любую сессию, подделать `state.json` с `session.pct=96`, отправить любой запрос. Claude должен получить reason в контексте и ответить сохранениями.

## Что НЕ делаем (YAGNI)

- Не пишем отдельные скрипты `autosave-*.sh` — всё живёт в существующих.
- Не парсим `ccusage` — Claude Code сам отдаёт нужные поля.
- Не добавляем сетевые вызовы в OAuth usage API — у нас уже есть данные.
- Не делаем конфигурируемые пороги — 95/99 зашиты. Если понадобится, вытащим в `config.json` позже.
- Не делаем отдельный кэш `usage.json` — используем существующий `state.json`.

## Git commit message (проект)

```
feat: AutoSave trigger при приближении usage limits

statusline.sh дампит rate_limits.{session,weekly}.{pct,resets_at} в state.json.
hooks/stop.sh при session≥95% или weekly≥99% возвращает decision:block с
инструкцией запустить /saveplan и /closeday. Anti-loop через fired_for==resets_at.
```

## Trade-offs

- **Плюс:** ноль новых файлов, zero-dependency, использует нативные поля Claude Code.
- **Плюс:** автосейв успеет до отключения — 99% weekly оставляет ~1% буфера на сохранения.
- **Минус:** один автосейв на окно — если Claude не смог выполнить `/saveplan`/`/closeday` (редкий случай), повтора не будет до резета.
- **Минус:** latency до триггера — до одного statusLine tick (≤300 мс) с момента, когда rate_limits обновились на стороне Claude Code.
