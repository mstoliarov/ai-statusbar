# ai-statusbar

Real-time status bar for [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code).

```
.ai-statusbar [master*] │ Sonnet 4.6 │ ctx ████░░░░░░ 49% / 200k │ usage/d █████░░░░░ 53% (3h 20m) │ usage/w ████░░░░░░ 42% (2d 10h) │ tok 3k/63k │ $2.75 │ 🔧 8 req │ 📝 +10/-3 │ ram ███████░░░ 12.5/16G
```

## Features

| Element | Description |
|---------|-------------|
| `folder [branch*]` | Working directory + git branch (`*` = uncommitted changes) |
| `Sonnet 4.6` | Current model name |
| `ctx ████ 49% / 200k` | Context window usage with color thresholds; size in magenta when Extra Usage (1M) |
| `extra 1.0M` | Extra Usage badge — shown only when context window is 1M tokens |
| `usage/d █████ 53% (3h 20m)` | 5-hour rate limit + time until reset |
| `usage/w ████ 42% (2d 10h)` | 7-day rate limit + time until reset |
| `tok 3k/63k` | Session tokens: input (green) / output (red) |
| `$1.50` | Session cost (USD) |
| `🔧 8 req` | Tool calls in current session |
| `📝 +10/-3` | Lines added / removed |
| `mem: 402 MB` | Claude Code process memory |
| `ram ███████░░░ 12.5/16G` | System RAM usage |

All elements are individually toggleable via `/statusbar`.

## Install

Bash (Git Bash / WSL / Linux):
```bash
git clone https://github.com/mstoliarov/ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
source ~/.bashrc
```

PowerShell:
```powershell
git clone https://github.com/mstoliarov/ai-statusbar "$env:USERPROFILE\.ai-statusbar"
bash "$env:USERPROFILE\.ai-statusbar\install.sh"
```

Restart Claude Code — the status bar appears automatically.

### Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- Git Bash (Windows) or POSIX shell (Linux/macOS)
- `jq` — downloaded automatically by `install.sh`

### Cross-platform

Works on **Windows** (Git Bash) and **Linux/WSL**.

WSL with shared Windows install:

```bash
ln -s /mnt/c/Users/YOUR_USER/.ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
```

## Usage

### `/statusbar` — configure elements

Type `/statusbar` in Claude Code. A multiselect UI appears with three pages of elements to toggle on/off:

- **General**: workspace, model, context, extra_ctx, tokens
- **Usage**: cost, daily_limit, weekly_limit, requests
- **System**: lines, claude_ram, ram

Select any elements → status bar enables automatically.
Deselect all → status bar disables automatically.

### Quick enable/disable

```
/statusbar on
/statusbar off
```

Or from terminal:

Bash:
```bash
bash ~/.ai-statusbar/toggle.sh on
bash ~/.ai-statusbar/toggle.sh off
```

PowerShell:
```powershell
bash "$env:USERPROFILE\.ai-statusbar\toggle.sh" on
bash "$env:USERPROFILE\.ai-statusbar\toggle.sh" off
```

Settings are saved to `~/.ai-statusbar/config.json` and take effect immediately.

## Update

```bash
cd ~/.ai-statusbar && git pull
```

PowerShell:
```powershell
cd "$env:USERPROFILE\.ai-statusbar"; git pull
```

No restart needed — changes take effect on the next prompt.

## Uninstall

**1. Remove the status bar from Claude Code settings:**

Bash (Git Bash / WSL / Linux):
```bash
~/bin/jq 'del(.statusLine) | del(.hooks.PostToolUse) | del(.hooks.Stop)' \
  ~/.claude/settings.json > ~/.claude/settings.json.tmp && \
  mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

PowerShell:
```powershell
$s = "$env:USERPROFILE\.claude\settings.json"
(Get-Content $s | ConvertFrom-Json) |
  Select-Object -Property * -ExcludeProperty statusLine |
  ForEach-Object { $_.hooks.PSObject.Properties.Remove('PostToolUse'); $_.hooks.PSObject.Properties.Remove('Stop'); $_ } |
  ConvertTo-Json -Depth 10 | Set-Content $s
```

**2. Delete the repository:**

Bash:
```bash
rm -rf ~/.ai-statusbar
```

PowerShell:
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.ai-statusbar"
```

**3. Remove jq (optional):**

Bash:
```bash
rm -f ~/bin/jq ~/bin/jq.exe
```

PowerShell:
```powershell
Remove-Item -Force "$env:USERPROFILE\bin\jq.exe" -ErrorAction SilentlyContinue
```

Restart Claude Code — the status bar will be gone.

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
| `toggle.sh` | Enable/disable statusLine (`on` / `off` / toggle) |
| `hooks/post-tool.sh` | PostToolUse hook — request counter, lines counter |
| `hooks/stop.sh` | Stop hook — daily/weekly usage tracking, cost estimate |
| `commands/statusbar.md` | `/statusbar` slash command definition |
| `config.json` | Element visibility config (gitignored) |
| `state.json` | Session state (gitignored) |

## License

MIT
