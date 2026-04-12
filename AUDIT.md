# AI Statusbar — Полный аудит реализации

## Общая архитектура

```
Claude Code
├─ statusLine → statusline.sh           (рендеринг строки состояния)
├─ PostToolUse → hooks/post-tool.sh     (счётчик запросов и строк)
└─ Stop → hooks/stop.sh                 (накопление usage, cost)
```

---

## Компоненты

### 1. statusline.sh — главный рендерер (420 строк)

**Входные данные:**
- Получает JSON через stdin от Claude Code
- Читает `config.json` (настройки видимости элементов)
- Читает `state.json` (сессионное состояние)
- Читает `~/.claude/.credentials.json` (для определения API mode)

**Парсинг JSON (одним вызовом jq):**
```bash
workspace.current_dir, model.display_name, context_window.*, 
rate_limits.five_hour.*, rate_limits.seven_day.*, cost.total_cost_usd,
cost.total_lines_added/removed
```

**Элементы статусбара:**

| Элемент | Описание | Формат |
|---------|----------|--------|
| `workspace` | Папка + git branch | `folder [branch*]` |
| `model` | Название модели | `Sonnet 4.6` |
| `context` | Контекстное окно | `ctx ████░░ 49% / 200k` |
| `daily_limit` | 5-часовой лимит | `usage/d █████ 53% (2h 30m)` |
| `weekly_limit` | 7-дневный лимит | `usage/w ████ 42% (2d 10h)` |
| `tokens` | Токены сессии | `tok 3k/63k` (input/output) |
| `cost` | Стоимость | `$2.75` или `$1.23/$5.00` (Extra Usage) |
| `requests` | Счётчик запросов | `🔧 8 req` |
| `lines` | Строки кода | `📝 +10/-3` |
| `claude_ram` | RAM процесса Claude | `mem: 402 MB` |
| `ram` | Системная RAM | `ram ███████░░░ 12.5/16G` |

**Кэширование:**
- **RAM:** 30 секунд (Windows: PowerShell call, Linux: `/proc/meminfo`)
- **Extra Usage balance:** 1 час (фондовый fetch с `Retry-After` backoff)

**Цветовая схема:**
- `< 50%` → зелёный
- `50-79%` → жёлтый
- `≥ 80%` → красный
- `MAGENTA` → Extra Usage (1M контекст)

---

### 2. hooks/post-tool.sh — PostToolUse хук

**Назначение:**
- Считает количество вызовов инструментов
- Считает строки для `Write`/`Edit`
- Определяет новую сессию по PID

**Логика определения сессии:**
```bash
if .claude_pid != $pid then
  .claude_pid = $pid | .requests_count = 1 | .lines_count = $lines
else
  .requests_count++ | .lines_count += $lines
end
```

---

### 3. hooks/stop.sh — Stop хук

**Назначение:**
- Накопление daily/weekly токенов
- Расчёт стоимости (~$3/$15 за 1M токенов)
- Обновление `state.json`

**Трекеры:**
- `usage.today` + `usage.today_tokens` (сброс при смене дня)
- `usage.week_start` + `usage.week_tokens` (сброс при смене недели)

---

### 4. toggle.sh — вкл/выкл

```bash
# on
jq '.statusLine = {"type":"command","command":"bash ~/.ai-statusbar/statusline.sh"}'

# off
jq 'del(.statusLine)'
```

---

### 5. commands/statusbar.md — slash-команда

**3 страницы AskUserQuestion (multiSelect):**
1. **General:** workspace, model, context, tokens
2. **Usage:** cost, daily_limit, weekly_limit, requests
3. **System:** lines, claude_ram, ram

**Логика:**
- Выбрано = `true`, не выбрано = `false`
- Пустой выбор → `toggle.sh off`
- Любой выбор → `toggle.sh on`

---

## Файловая структура

```
~/.ai-statusbar/
├── statusline.sh          # рендерер
├── install.sh             # установщик
├── toggle.sh              # вкл/выкл
├── update-state.sh        # утилита обновления state.json
├── commands/
│   └── statusbar.md       # slash-команда
├── hooks/
│   ├── post-tool.sh       # PostToolUse
│   └── stop.sh            # Stop
├── config.json            # видимость элементов (gitignore)
├── state.json             # сессионное состояние (gitignore)
├── .ram_cache             # кэш RAM (30s)
├── .usage_cache           # кэш Extra Usage (1h)
└── .usage_retry_after     # Rate limit backoff
```

---

## Детали реализации

### Модели и контекст

```bash
get_default_ctx_size() {
  *"gemma4:31b-cloud"* → 258000
  * → 200000
}
```

### Extra Usage detection

- `ctx_size >= 1000000` → Extra Usage badge
- API mode: `rateLimitTier != "default_claude_ai"`

### Прогресс-бар (10 символов)

```bash
make_bar() {
  filled=$(( pct * 10 / 100 ))
  bar = "█" × filled + "░" × (10 - filled)
}
```

### Форматирование чисел

- `fmt_num()`: 1234567 → `1.2M`, 45000 → `45k`
- `fmt_duration()`: 7320 → `2h 2m`, 90061 → `1d 1h`

---

## Производительность

1. **Один jq call** для парсинга всех полей statusLine JSON
2. **Один PowerShell call** для RAM (Windows)
3. **Кэш RAM 30s** для избежания overhead
4. **Фоновый fetch** Extra Usage balance (не блокирует рендер)
5. **Stale-while-revalidate** для кэшей

---

## Безопасность

- Нет внешних вызовов кроме Anthropic API
- `curl` с `--max-time 5` и `--ssl-no-revoke` (Windows)
- Временные файлы `.tmp` с атомарным `mv`
- Проверка валидности JSON перед записью

---

## Текущая конфигурация пользователя

```json
{
  "workspace": true,
  "model": true,
  "context": true,
  "tokens": true,
  "cost": false,          // скрыто
  "daily_limit": true,
  "weekly_limit": true,
  "requests": true,
  "lines": false,         // скрыто
  "claude_ram": true,
  "ram": true
}
```

**state.json:**
- Токены: 796501 input / 6468 output
- Запросов: 1
- PID: 550462

---

## Наблюдения

1. **Масштабируемость:** Поддержка Windows (Git Bash) и Linux/WSL
2. **Расширяемость:** Новые элементы добавляются через `show_el()` + config
3. **Отказоустойчивость:** Дефолтные значения при отсутствии данных
4. **Debug:** Логирование в `/tmp/statusbar_debug.log`
