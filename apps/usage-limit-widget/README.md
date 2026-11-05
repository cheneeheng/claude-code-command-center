# usage-limit-widget

A small Windows widget for your Claude usage limits. It hides at the top edge of the primary
monitor, leaving a 2px handle. Hover that spot to reveal your plan and two rows, the 5-hour
session limit and the 7-day weekly limit. Each row has a bar, the percentage used, the reset
time, and the time left until the reset.

```
     5h  ▮▮▮▮▯▯▯▯▯▯  42%  Thu 12:29   2h9m
Pro  7d  ▮▮▮▮▮▮▮▮▯▯  86%  Mon 13:19   4d2h
```

Each bar has 10 segments of 10%, so you can count the used share at a glance. The segment in
progress fills partway, and a bar turns red at 80%.

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
