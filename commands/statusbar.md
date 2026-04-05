---
name: statusbar
description: Configure the Claude Code status bar — toggle elements on/off, enable/disable the entire bar
argument-hint: "[on|off]"
allowed-tools: Bash, AskUserQuestion
---

# AI Status Bar Configuration

## Handling arguments

- **`on`**: Enable status bar — run `bash ~/.ai-statusbar/toggle.sh on`
- **`off`**: Disable status bar — run `bash ~/.ai-statusbar/toggle.sh off`
- **No arguments or anything else**: Show interactive config (see below)

## Interactive config (no arguments)

1. Use `AskUserQuestion` with **3 questions** (do NOT read any files beforehand):

   **Question 1** (multiSelect) — header: "General", question: "Select elements to show on status bar (1/3):"
   - workspace — "Working directory and git branch"
   - model — "Model name (e.g. Opus 4.6)"
   - context — "Context window progress bar"
   - extra_ctx — "Extra Usage badge (shown only when context is 1M)"
   - tokens — "Total tokens used"

   **Question 2** (multiSelect) — header: "Usage", question: "Select elements to show on status bar (2/3):"
   - cost — "Session cost in USD"
   - daily_limit — "Daily rate limit bar + time to reset"
   - weekly_limit — "Weekly rate limit bar + time to reset"
   - requests — "Tool request count"

   **Question 3** (multiSelect) — header: "System", question: "Select elements to show on status bar (3/3):"
   - lines — "Lines added/removed"
   - claude_ram — "Claude process memory"
   - ram — "System RAM progress bar"

2. After user responds:
   - For Q1-Q3: **selected = ON (`true`)**, **not selected = OFF (`false`)**
   - Apply changes silently using **two parallel Bash calls**, both with `run_in_background: true`:
     1. Write `~/.ai-statusbar/config.json` via `cat > ~/.ai-statusbar/config.json << 'EOF'` with the full JSON built from selections
     2. Run `bash ~/.ai-statusbar/toggle.sh off` (if no elements selected) or `bash ~/.ai-statusbar/toggle.sh on` (if any selected)
   - **Do NOT output anything after applying changes** — no summaries, no confirmations, no text
