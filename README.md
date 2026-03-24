# ai-statusbar

A live status bar plugin for [Claude Code](https://claude.ai/claude-code) and Gemini CLI.

![status bar preview](https://img.shields.io/badge/Claude_Code-plugin-blueviolet)

```
.PROJECTS [master*] │ Sonnet 4.6 │ ████░░░░░░ 42% │ 🔧 12 req │ 📝 340 lines
```

## Features

- **Inline status bar** — appears inside Claude Code terminal (via `statusLine`)
- **Progress bar** — context window usage with color thresholds (green / yellow / red)
- **Git info** — current branch + dirty indicator (`*`)
- **Model name** — active Claude/Gemini model
- **Request counter** — total tool calls in session
- **Lines of code** — lines written via Write/Edit tools
- **Cost estimate** — USD cost after each response (via terminal overlay)
- **Gemini CLI support** — wraps `gemini` command with the same status bar

## Install

```bash
git clone https://github.com/mstoliarov/ai-statusbar ~/.ai-statusbar
bash ~/.ai-statusbar/install.sh
```

Then restart Claude Code or reload your shell:
```bash
source ~/.bashrc
```

## Requirements

- Claude Code CLI
- `jq` and `gum` — downloaded automatically by `install.sh`
- Git Bash (Windows) or any POSIX shell

## How it works

```
PostToolUse hook (post-tool.sh)
  └─ increments requests_count + counts lines from Write/Edit

Stop hook (stop.sh)
  └─ calculates cost, context %, resets counters

statusline.sh
  └─ reads stdin JSON from Claude Code + state.json → outputs colored status line
```

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-command setup |
| `statusline.sh` | Claude Code inline status bar |
| `render.sh` | Terminal overlay (uses gum) |
| `hooks/post-tool.sh` | PostToolUse hook — counters |
| `hooks/stop.sh` | Stop hook — cost + reset |
| `gemini-wrapper.sh` | Gemini CLI wrapper |
| `update-state.sh` | Utility to patch state.json |

## License

MIT
