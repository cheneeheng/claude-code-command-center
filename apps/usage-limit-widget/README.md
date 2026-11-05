# usage-limit-widget

A small Windows widget for your Claude usage limits. It hides at the top edge of the primary
monitor, leaving a 2px handle. Hover that spot to reveal two rows, the 5-hour session limit and
the 7-day weekly limit, each with a bar, the percentage used, and when it resets.

```
5h  ██████░░░░░░░░░░░░░░░  42%  ·  18:32 (2h10m)
7d  ██░░░░░░░░░░░░░░░░░░░  11%  ·  Tue 09:00 (4d3h)
```

## Install

Needs Windows and [`uv`](https://docs.astral.sh/uv/). The widget is stdlib-only (Python 3.11+
with tkinter).

```powershell
.\usage-limit-widget-setup.ps1                     # register the task and start the widget now
.\usage-limit-widget-setup.ps1 -Action uninstall   # stop and remove the task
```

Install registers `\ClaudeAutomation\usage-limit-widget\widget`. The task starts the widget at
logon and restarts it every hour, which also brings it back after you quit it. You can also
install it through [`setup/command-center.ps1`](../../setup/) as `usage-limit-widget`.

To run it once without the task: `pythonw claude_usage_widget.pyw`.

## Use

- Hover the top-center edge of the screen to show the panel. Move away to hide it.
- Press `r` on the panel to fetch usage now. Otherwise it fetches every 5 minutes.
- Press `q` on the panel to quit.

## How it works

It reads the OAuth token Claude Code stores in `.credentials.json` in your Claude config dir
(`C4_CLAUDE_DIR`, then `CLAUDE_CONFIG_DIR`, then `~/.claude`). It sends one GET to the usage
endpoint Claude Code's own `/usage` uses, with your installed Claude Code version (from
`claude --version`) as the User-Agent. Nothing else leaves your machine.

That endpoint is **undocumented**, so it can change or break without notice. A `429` means the
account is being rate limited, and the widget retries at the next poll.

Linux and macOS are not supported: the widget uses Windows APIs for the cursor position and
screen size.
