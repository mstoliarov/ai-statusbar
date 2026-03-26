# Plan: Gemini CLI Status Bar

## Approach
Use Gemini CLI hooks system to collect data and display a status line via stderr.
Same visual format as Claude status bar. Cross-platform: bash scripts callable
from both Linux (bash -c) and Windows (PowerShell → Git Bash).

## Data Available via Hooks
- `AfterModel`: tokens (usageMetadata.promptTokenCount, candidatesTokenCount), model (llm_request.model)
- `AfterTool`: tool name (for request counter)
- Base fields in all hooks: cwd, session_id, timestamp, hook_event_name
- NOT available: context window %, daily/weekly rate limits

## Files to Create

### hooks/gemini-after-model.sh
- Reads stdin JSON (AfterModel payload)
- Extracts: model, input_tokens, output_tokens
- Calculates cost (by model pricing table)
- Updates state.json (provider=gemini, tokens, cost, model)
- Builds colored status line (same format as statusline.sh)
- Writes status line to stderr (visible in Gemini TUI between responses)
- Outputs `{}` to stdout (required by Gemini CLI)

### hooks/gemini-after-tool.sh
- Increments requests_count in state.json
- Outputs `{}`

### hooks/gemini-session-start.sh
- Initializes state.json (provider=gemini, cwd, session start time)
- Resets requests_count, lines_count
- Outputs `{}`

## Gemini settings.json (~/.gemini/settings.json)
Add hooks section:
```json
"hooks": {
  "AfterModel": [{"command": "bash ~/.ai-statusbar/hooks/gemini-after-model.sh"}],
  "AfterTool":  [{"command": "bash ~/.ai-statusbar/hooks/gemini-after-tool.sh"}],
  "SessionStart": [{"command": "bash ~/.ai-statusbar/hooks/gemini-session-start.sh"}]
}
```

## Status Line Format (stderr output)
```
.PROJECTS [main] │ gemini-2.5-pro │ API │ tok 4.2k │ $0.0012 │ 🔧 3 req
```
Uses same ANSI colors, same SEP separator, same show_el() config.json logic.

## Gemini Model Pricing (for cost calculation)
| Model | Input $/1M | Output $/1M |
|---|---|---|
| gemini-2.5-pro | 1.25 | 10.00 |
| gemini-2.5-flash | 0.30 | 2.50 |
| gemini-1.5-pro | 1.25 | 5.00 |
| gemini-1.5-flash | 0.075 | 0.30 |
| gemini (default) | 0.30 | 2.50 |

## Cross-Platform Notes
- Command `bash ~/.ai-statusbar/hooks/...` works on both:
  - Linux: Gemini runs `bash -c "bash ..."` directly
  - Windows: Gemini runs `powershell.exe -Command "bash ..."`, Git Bash handles it
- ANSI colors work in Windows Terminal and Linux terminals
- jq and gum binaries: need platform detection (~/bin/jq.exe on Windows, ~/bin/jq on Linux)

## Elements Shown (respects config.json show_el)
- folder + git branch (always)
- model name
- auth type (API vs SUB — detect via GOOGLE_API_KEY env var)
- token counter
- cost per session
- requests counter
- NOT: context window (not in hook data), daily/weekly limits

## install.sh additions
- Patch ~/.gemini/settings.json with hooks (if Gemini CLI is detected)
- Mention Gemini CLI setup in output
