# ai-statusbar

Live status bar plugin for [Claude Code](https://claude.ai/claude-code) and Gemini CLI.

```
.PROJECTS [master*] │ Sonnet 4.6 │ ctx ████░░░░░░ 42% / 200k │ usage/d ██░░░░░░░░ 18% / 1M │ usage/w █░░░░░░░░░ 9% / 5M │ tok 12.3k │ 🔧 8 req │ 📝 120 lines
```

## Features

| Element | Description |
|---------|-------------|
| `folder [branch*]` | Working directory + git branch, `*` = dirty |
| `ctx ████ 42% / 200k` | Context window usage — green → yellow → red |
| `usage/d ██ 18% / 1M` | Daily token usage vs limit (blue) |
| `usage/w █ 9% / 5M` | Weekly token usage vs limit (blue) |
| `tok 12.3k` | Session tokens (input + output) |
| `🔧 8 req` | Tool calls since Claude CLI started |
| `📝 120 lines` | Lines written via Write/Edit tools |
| Terminal overlay | Cost estimate + tokens after each response (via `gum`) |
| Gemini CLI | Same status bar for `gemini` command |

## Install

```bash
git clone https://github.com/mstoliarov/ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
source ~/.bashrc
```

Restart Claude Code — the status bar appears automatically.

## Requirements

- Claude Code CLI
- Git Bash (Windows) or any POSIX shell (Linux/macOS)
- `jq` and `gum` — **downloaded automatically** by `install.sh`

## Configuration

Edit `~/.ai-statusbar/state.json` to adjust usage limits:

```json
"usage": {
  "daily_limit": 1000000,
  "weekly_limit": 5000000
}
```

## How it works

```
Claude Code
  ├─ PostToolUse → hooks/post-tool.sh
  │     └─ increments requests_count (resets on new claude process)
  │        counts lines for Write/Edit tools
  │
  ├─ Stop → hooks/stop.sh
  │     └─ accumulates daily/weekly token usage with date rollover
  │        calculates cost estimate
  │        renders terminal overlay via render.sh
  │
  └─ statusLine → statusline.sh
        └─ reads Claude Code JSON + state.json
           outputs colored inline status bar

Gemini CLI
  └─ gemini-wrapper.sh (source in ~/.bashrc)
        └─ wraps gemini command, calls render.sh after response
```

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-command setup (downloads jq + gum, patches settings.json) |
| `statusline.sh` | Claude Code inline status bar |
| `render.sh` | Terminal overlay after each response (uses gum) |
| `hooks/post-tool.sh` | PostToolUse hook — request counter, lines counter |
| `hooks/stop.sh` | Stop hook — usage tracking, cost estimate |
| `gemini-wrapper.sh` | Gemini CLI wrapper function |
| `update-state.sh` | Utility to patch state.json via jq |
| `state.json` | Session state (excluded from git) |

## License

MIT
