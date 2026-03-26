# AI Status Bar Configuration

Read the status bar config from `~/.ai-statusbar/config.json` and show the user a clear overview of all elements with their current state.

## Display format

Show a table like this:

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

## Handling arguments

The user may pass arguments after `/statusbar`. Handle them as follows:

- **No arguments**: Show the table above and ask "What would you like to change?"
- **`on` / `off`**: Toggle the entire status bar via `bash ~/.ai-statusbar/toggle.sh`
- **`<element> on/off`**: Toggle a specific element (e.g., `/statusbar ram off`). Update config.json by setting `.show.<element>` to `true` or `false`.
- **`all on` / `all off`**: Enable or disable all elements at once.
- **Number(s)**: Toggle elements by number from the table (e.g., `/statusbar 3 5` toggles daily_limit and tokens).

After any change, update `~/.ai-statusbar/config.json` and show the updated table.

## Important

- If `config.json` does not exist, create it with all elements set to `true`.
- Always preserve the JSON format (use jq if available at `~/bin/jq`).
- Do NOT modify `~/.claude/settings.json` unless the user says `/statusbar on` or `/statusbar off`.
