# statusline-hook

A clean, rate-limit-first statusline for Claude Code. Each turn it prints up to three aligned rows:

```
Opus 5.5 high   ctx ━━━━────── 42% · ◷ 1h 12m · ⧗ 15:43 (59m) · $1.23
                5h  ━━━━━━──── 63%  ↺ 17:00 (2h 14m)
                7d  ━━━━━━━━── 85%  ↺ Thu 17:00 (5d 7h)
```

- **Row 1:** model and reasoning effort (shown when the model supports effort), context-window
  gauge, session runtime (`◷`), prompt cache expiry (`⧗`), session cost.
- **Cache:** the local time the main session's prompt cache expires and, in brackets, how long
  until it does, or `expired`. It assumes a one-hour cache, counted from the last main-session
  reply in the transcript (subagent and synthetic replies are ignored). The statusline only
  redraws on activity, so the countdown is live only with a `refreshInterval` set; the expiry
  time is right either way. The segment is left out until the session's first reply.
- **Rows 2–3:** your 5-hour and 7-day rate-limit usage, with the local time each window resets
  and, in brackets, how long until it does.
  Claude Code sends these only to Pro/Max subscribers, after the session's first response; a row
  is left out while its window is absent.

Colour carries meaning, not decoration: every gauge turns green below 50%, yellow below 80%, and red
from 80%. Labels, separators, and reset times are dimmed. Rows 2–3 stay under about 55 characters
and row 1 under about 75, so it fits a split pane. Plain Unicode only, so no Nerd Font is needed.

Two equivalent single-file scripts. Pick the one for your shell:

| File | Needs | Notes |
|------|-------|-------|
| `statusline-hook.sh` | `bash`, [`jq`](https://jqlang.org/) | Linux, macOS, and Git Bash on Windows. |
| `statusline-hook.ps1` | Windows PowerShell 5.1 or PowerShell 7 | No modules. |

Bad or unexpected input never breaks your session: the script prints nothing and exits 0.

## Install

**With a setup script.** It copies the script into your Claude config dir and wires the
`statusLine` key in `settings.json`, keeping your other settings. Use the one for your shell:

```powershell
./statusline-hook-setup.ps1                  # PowerShell variant (default)
./statusline-hook-setup.ps1 -Variant sh      # bash variant
./statusline-hook-setup.ps1 -Action uninstall
./statusline-hook-setup.ps1 -ClaudeDir D:\claude   # a config dir other than ~/.claude
```

```bash
./statusline-hook-setup.sh                   # bash variant (default), needs jq
./statusline-hook-setup.sh --variant ps1     # PowerShell variant
./statusline-hook-setup.sh uninstall
./statusline-hook-setup.sh --claude-dir ~/claude   # a config dir other than ~/.claude
```

Both run the PowerShell variant with `pwsh` when PowerShell 7 is installed, and with `powershell`
otherwise. It also removes scripts left behind by earlier versions of this hook. This tool is also
managed by the repo-wide [`setup/`](../../setup/) installer
(`command-center.ps1 install -Member statusline-hook`).

**By hand.** Copy one script into `~/.claude/`, then add it to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-hook.sh"
  }
}
```

For PowerShell, use `"command": "pwsh -NoProfile -File ~/.claude/statusline-hook.ps1"` (or
`powershell` instead of `pwsh` on a machine without PowerShell 7).

## Quota export

Claude Code sends your rate-limit usage only to the statusline, never to hooks. So that a hook can
act on it, for example a guard that stops work before you hit your limit, each turn that carries
`rate_limits` the statusline overwrites one file,
`~/.claude/statusline/latest/rate-limits.jsonl`, with a single line:

```json
{"session_id":"…","ts":1763400000000,"data":{"rate_limits":{"five_hour":{…},"seven_day":{…}}}}
```

`ts` is epoch milliseconds, and `rate_limits` is exactly what Claude Code sent. The file never
grows, every window writes the same account-wide reading, and a reader never sees half a line. The
output on screen is the same either way.

The export is on by default. To turn it off, set `C4_STATUSLINE_DISABLE_EXPORT=1` (or `true`,
`yes`), most simply in the `env` block of `~/.claude/settings.json`:

```json
{ "env": { "C4_STATUSLINE_DISABLE_EXPORT": "1" } }
```

## Development

The `fixtures/` folder is the spec: each `<case>.json` is the stdin Claude Code sends, and
`<case>.out` is the exact expected output, with each ESC byte written as `\e`. Both scripts must
pass every fixture:

```bash
bash tests/golden.sh bash statusline-hook.sh
bash tests/golden.sh pwsh -NoProfile -File statusline-hook.ps1
bash tests/smoke.sh     # installs each variant with each setup script, runs it (needs pwsh + jq)
bash tests/export.sh bash statusline-hook.sh                    # the quota export, per port
bash tests/export.sh pwsh -NoProfile -File statusline-hook.ps1
```

The export test points `HOME` and `USERPROFILE` at a temp dir, and the golden and smoke tests
set `C4_STATUSLINE_DISABLE_EXPORT=1`, so no test touches your real reading.

The harness pins `TZ=UTC` and the clock (`C4_STATUSLINE_NOW`, epoch seconds, a test-only
override) so reset times and time left are deterministic. PowerShell on Windows ignores `TZ` and
always uses the system time zone, so on a machine that isn't set to UTC, the PowerShell run shows
reset-time differences only. CI runs everything in UTC on Ubuntu and Windows.
