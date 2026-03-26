# ai-statusbar

Real-time status bar for [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code).

```
.ai-statusbar [master*] │ Opus 4.6 │ ctx ██░░░░░░░░ 25% / 200k │ usage/d ████░░░░░░ 45% │ usage/w █░░░░░░░░░ 16% │ tok 7k │ $1.50 │ 🔧 8 req │ 📝 +10/-3 │ mem: 402 MB │ ram ███████░░░ 12.5/16G
```

## Features

| Element | Description |
|---------|-------------|
| `folder [branch*]` | Working directory + git branch (`*` = uncommitted changes) |
| `Opus 4.6` | Current model name (magenta) |
| `ctx ████ 25% / 200k` | Context window usage with color thresholds |
| `usage/d ████ 45%` | 5-hour rate limit (blue) |
| `usage/w █ 16%` | 7-day rate limit (blue) |
| `tok 7k` | Session tokens (input + output) |
| `$1.50` | Session cost (USD) |
| `🔧 8 req` | Tool calls in current session |
| `📝 +10/-3` | Lines added (green) / removed (red) |
| `mem: 402 MB` | Claude Code process memory |
| `ram ███████░░░ 12.5/16G` | System RAM usage with progress bar |

All elements are configurable — enable/disable via `/statusbar` command.

## Install

```bash
git clone https://github.com/mstoliarov/ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
source ~/.bashrc
```

Restart Claude Code — the status bar appears automatically.

### Cross-platform

Works on **Windows** (Git Bash / PowerShell) and **Linux/WSL**.

For WSL with shared codebase, symlink to the Windows install:

```bash
ln -s /mnt/c/Users/YOUR_USER/.ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- Git Bash (Windows) or POSIX shell (Linux/macOS)
- `jq` — downloaded automatically by `install.sh`

## Usage

### `/statusbar` — configure elements

Type `/statusbar` in Claude Code to see current configuration:

```
AI Status Bar Configuration
===========================
 #  Element      Status
 1  model        ON
 2  context      ON
 3  daily_limit  ON
 4  weekly_limit ON
 5  tokens       ON
 6  cost         ON
 7  requests     ON
 8  lines        ON
 9  claude_ram   ON
10  ram          ON
```

Toggle elements:

| Command | Action |
|---------|--------|
| `/statusbar` | Show config table |
| `/statusbar 3 5` | Toggle elements by number |
| `/statusbar ram off` | Disable specific element |
| `/statusbar all off` | Disable all elements |
| `/statusbar on` / `off` | Enable/disable entire status bar |

Settings are saved to `~/.ai-statusbar/config.json` and take effect immediately.

## How it works

```
Claude Code
  ├─ statusLine → statusline.sh
  │     └─ reads Claude Code JSON (stdin) + state.json + config.json
  │        outputs colored inline status bar
  │
  ├─ PostToolUse → hooks/post-tool.sh
  │     └─ increments request counter, counts lines for Write/Edit
  │
  └─ Stop → hooks/stop.sh
        └─ accumulates daily/weekly token usage, calculates cost
```

### Performance

- All statusLine JSON fields parsed in a **single jq call**
- System RAM + Claude process memory fetched in **one PowerShell call** (Windows)
- RAM data **cached for 30 seconds** to avoid repeated PowerShell startup overhead
- On Linux: reads `/proc/meminfo` directly (~1ms)

## Files

| File | Purpose |
|------|---------|
| `statusline.sh` | Main status bar renderer (receives JSON from Claude Code) |
| `install.sh` | One-command setup (downloads jq, patches settings.json) |
| `hooks/post-tool.sh` | PostToolUse hook — request counter, lines counter |
| `hooks/stop.sh` | Stop hook — daily/weekly usage tracking, cost estimate |
| `toggle.sh` | Enable/disable statusLine in settings.json |
| `commands/statusbar.md` | `/statusbar` slash command definition |
| `config.json` | Element visibility config (gitignored) |
| `state.json` | Session state (gitignored) |

## License

MIT
