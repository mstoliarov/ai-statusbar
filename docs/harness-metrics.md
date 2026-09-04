# Status-bar metrics available per harness

Verified on 2026-09-04 against the installed builds on this machine, by reading
each harness's own code/binary — not documentation, which was stale or wrong for
all three non-Claude harnesses.

Each harness renders its status bar through a **different, incompatible
mechanism**. Only Claude Code and Agy route through `statusline.sh`; Codex and
Hermes render their own and are configured through their own config files.

| | Claude Code | Agy / Antigravity | Codex | Hermes |
|---|---|---|---|---|
| Mechanism | `statusLine` hook → `statusline.sh` | `statusLine` hook → `statusline.sh` | native TUI | native TUI (Python) |
| Config | `~/.ai-statusbar/config.json` | same file | `[tui] status_line` in `~/.codex/config.toml` | `display.status_bar.fields` in profile `config.yaml` |
| Enable/disable | `/statusbar on\|off` | its own `statusLine.enabled` | `status_line = []` | `/statusbar` (in-memory toggle), `display.statusbar: top\|off` |
| Per-field toggles | yes | yes (same config) | yes (ordered array) | yes (allowlist, fixed order) |

## Claude Code

Full field set — see the README table. Richest of the four: it is the only
harness that supplies cost, lines added/removed and a tool-request count, and
the only one where `statusline.sh` also adds process/system RAM.

## Agy / Antigravity

Wired via `statusLine` in `~/.gemini/antigravity-cli/settings.json`, pointing at
the same `statusline.sh`. Sends the same `cwd` / `model` / `context_window`
shape as Claude Code, so those segments work unchanged, plus:

- `product: "antigravity"` — the discriminator `statusline.sh` branches on.
- `quota."3p-weekly"` and `quota."gemini-weekly"` — two **weekly** pools by
  backend class, as `remaining_fraction` + `reset_in_seconds`. There is no
  5-hour/daily window, so the bar renders `3P/wk` and `Gem/wk` instead of
  `Usage/d` and `Usage/w`.
- No cost, no lines, no request counter — those segments are suppressed.
- No provider field; the provider tag is inferred from the model name.

Also present in its JSON but not currently rendered: `plan_tier`,
`agent_state`, `cycle_mode`, `artifact_count`, `task_count`, `sandbox.enabled`.

## Codex

Native only — no bash-hook seam. Configured as an **ordered array** of item
ids; unknown ids are ignored with an "Ignored invalid status line" warning
rather than an error. Codex also ships its own `/statusline` picker.

Item ids (kebab-case, extracted from the binary's string table and confirmed
against `codex doctor`'s live `title items` readout):

`activity`, `project-name`, `app-name`, `current-dir`, `run-state`,
`thread-title`, `git-branch`, `context-remaining`, `context-used`,
`five-hour-limit`, `weekly-limit`, `thread-credits`, `estimated-thread-cost`,
`codex-version`, `used-tokens`, `total-input-tokens`, `total-output-tokens`,
`thread-id`, `fast-mode`, `model-with-reasoning`, `task-progress`,
`hostname`, `pull-request-number`, `branch-changes`, `permissions`,
`approval`, `approval-mode`, `context-window-size`, `raw-output`,
`workspace-headline`, `model`, `reasoning`

Closest equivalents to this project's bar: `current-dir` + `git-branch`
(workspace), `model-with-reasoning`, `context-used` / `context-remaining`,
`five-hour-limit` + `weekly-limit` (usage/d + usage/w), `used-tokens`,
`estimated-thread-cost`. No RAM, no lines changed, no tool-request count.
`estimated-thread-cost`, `thread-credits` and `workspace-headline` are
Enterprise-workspace only and are omitted elsewhere.

## Hermes

Native only, rendered in `hermes-agent/cli.py`. `display.status_bar.fields` is
an **allowlist** — set it and only those fields show; omit the key entirely and
everything except `total_tokens` shows. Field order is fixed by the renderer;
the config controls visibility only.

Fields: `model`, `context_detail`, `context_pct`, `cache_hit`, `latency`,
`tps`, `compressions`, `bg_tasks`, `bg_processes`, `bg_subagents`, `goal`,
`duration`, `prompt_elapsed`, `idle_since`, `focus`, `yolo`, `stash`,
`battery`, `title`, `total_tokens`

`total_tokens` is opt-in only. `battery` additionally needs `display.battery:
true` (or `/battery on`) before it reads anything. Unique to Hermes:
`cache_hit` (prompt-cache hit rate), `latency`, `tps` (tokens/sec),
`compressions`, and background task/process/subagent counters.

Hermes has **no** cost, rate-limit or RAM segment in its bar, and no provider
name — although usage data does exist behind its `/usage` command and the
`session_model_usage` table, so a usage segment would require patching
`cli.py` itself.

`/statusbar` in Hermes is a hardcoded in-memory visibility toggle
(`cli.py`, `canonical == "statusbar"`); it takes no arguments and does not
persist. Persist visibility via `display.statusbar` instead.
