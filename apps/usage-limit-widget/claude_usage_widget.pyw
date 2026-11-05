"""
Claude usage edge-widget for Windows.

Hover your mouse directly over the top-center sliver of your primary
monitor to reveal current Claude usage (5h session / 7d weekly limits).
Move away and it slides back out of sight. "q" the panel to quit.

It reads the OAuth token Claude Code already stores locally at
~/.claude/.credentials.json and calls the usage endpoint Claude Code's
own /usage command uses internally. That endpoint is UNDOCUMENTED --
reverse-engineered from Claude Code's network traffic, not an official
API -- so it can change or break without notice. Nothing leaves your
machine except that one authenticated GET request to Anthropic.

Run with:   pythonw claude_usage_widget.pyw     (no console window)
Quit with:  "q" anywhere on the revealed panel ("r" re-fetches usage now)
Requires:   Python 3.11+ on Windows, stdlib only, no pip installs.

To auto-start at logon (and restart hourly): usage-limit-widget-setup.ps1
"""

import ctypes
import ctypes.wintypes
import functools
import json
import os
import shutil
import subprocess
import threading
import tkinter as tk
import urllib.error
import urllib.request
from datetime import UTC, datetime

# ---- config ----
POLL_MS = 60  # how often to check cursor position (ms)
EDGE_TRIGGER_PX = 3  # trigger-zone height at the very top edge
KEEP_PAD_X = 15  # extra width each side once visible (hysteresis)
HIDE_MARGIN_PX = 10  # extra height below panel once visible (hysteresis)
REFRESH_SECS = 300  # how often to re-fetch usage from Anthropic ("r" fetches now)
PAD, ROW_H = 6, 17  # one row per limit: label, bar, figures
PANEL_W, PANEL_H = 330, 2 * PAD + 2 * ROW_H
# The bar fills the width between them. FIGURES_W fits the widest figures,
# "100%  ·  Tue 09:00 (6d23h)" (136px in Segoe UI 9), plus a gap.
LABEL_W, FIGURES_W = 26, 150

# ---- look ----
BG, BORDER, FG, MUTED, TRACK = "#1f1f1f", "#3a3a3a", "#e8e8e8", "#9a9a9a", "#363636"
ACCENT, WARN = "#d97757", "#e5534b"  # Claude orange; red once usage is high
FONT, FONT_BOLD = ("Segoe UI", 9), ("Segoe UI Semibold", 9)

# five_hour = rolling session limit, seven_day = rolling weekly limit --
# these are the two caps a Claude subscription (Pro/Max) usage is tracked
# against; each resets independently on its own rolling window.
LABELS = {"five_hour": "5h", "seven_day": "7d"}


def claude_dir():
    # C4_CLAUDE_DIR is pathsep-separated; the first entry wins, as elsewhere
    # in this repo. Then Claude Code's own override, then the default.
    c4 = os.environ.get("C4_CLAUDE_DIR", "").split(os.pathsep)[0]
    return (
        c4
        or os.environ.get("CLAUDE_CONFIG_DIR")
        or os.path.join(os.path.expanduser("~"), ".claude")
    )


CREDS_PATH = os.path.join(claude_dir(), ".credentials.json")


def load_token():
    with open(CREDS_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["claudeAiOauth"]["accessToken"]


@functools.cache
def user_agent():
    """claude-code/<installed version>, read once per process (the hourly
    restart picks up upgrades). Bare claude-code if the CLI can't be run."""
    exe = shutil.which("claude")
    try:
        out = subprocess.run(
            [exe, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
            creationflags=subprocess.CREATE_NO_WINDOW,  # no console flash
        ).stdout.split()
        return f"claude-code/{out[0]}" if out else "claude-code"
    except (TypeError, OSError, subprocess.SubprocessError):
        return "claude-code"  # TypeError: claude not on PATH (exe is None)


def fetch_usage():
    token = load_token()
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": user_agent(),
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())


def pct(block):
    """Best-effort pull of a utilization percentage as an int (0-100),
    or None. Field names are guessed since the endpoint isn't documented --
    adjust here if Anthropic changes the response shape."""
    if not isinstance(block, dict):
        return None
    for key in ("utilization", "percent_used", "used_percentage", "usage_percentage"):
        if key in block:
            v = block[key]
            return round(v * 100) if v <= 1 else round(v)
    return None


def resets_at(block):
    if not isinstance(block, dict):
        return None
    for key in ("resets_at", "resetsAt", "reset_at"):
        if key in block:
            return block[key]
    return None


def parse_reset(value):
    """Turn a resets_at value (ISO string or epoch) into an aware UTC datetime."""
    if value is None:
        return None
    try:
        if isinstance(value, (int, float)):
            ts = value / 1000 if value > 1e12 else value
            return datetime.fromtimestamp(ts, tz=UTC)
        dt = datetime.fromisoformat(str(value))  # 3.11+ parses a trailing Z
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.astimezone(UTC)
    except (ValueError, OverflowError, OSError):
        return None


def format_delta(dt_utc):
    if dt_utc is None:
        return "?"
    secs = int((dt_utc - datetime.now(UTC)).total_seconds())
    if secs <= 0:
        return "now"
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days:
        return f"{days}d{hours}h"
    if hours:
        return f"{hours}h{mins}m"
    return f"{mins}m"


def format_abs(dt_utc):
    """24-hour local clock time, e.g. '18:32' or 'Tue 18:32' if not today."""
    if dt_utc is None:
        return "?"
    local = dt_utc.astimezone()  # convert to system local timezone
    now_local = datetime.now().astimezone()
    t = local.strftime("%H:%M")
    if local.date() != now_local.date():
        return local.strftime("%a") + " " + t
    return t


class Widget:
    def __init__(self):
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=BG)

        self.x = self.center_x()
        self.hidden_y = -PANEL_H + 2  # 2px sliver stays visible as a handle
        self.shown_y = 0
        self.root.geometry(f"{PANEL_W}x{PANEL_H}+{self.x}+{self.hidden_y}")

        self.canvas = tk.Canvas(
            self.root,
            bg=BG,
            highlightthickness=1,
            highlightbackground=BORDER,
        )
        self.canvas.pack(fill="both", expand=True)

        # "q" anywhere on the panel to quit, "r" to re-fetch usage now.
        self.root.bind("<q>", self.quit)
        self.refresh_now = threading.Event()
        self.root.bind("<r>", lambda event: self.refresh_now.set())

        # The fetch thread only writes self.data; all Tk calls stay on the
        # main thread (tkinter is not thread-safe).
        self.data = "Loading..."
        self.drawn = None
        self.visible = False
        threading.Thread(target=self.refresh_loop, daemon=True).start()
        self.root.after(POLL_MS, self.poll_cursor)

    @staticmethod
    def center_x():
        # Re-read every poll: docking, resolution or scaling changes move
        # the primary monitor's center after startup.
        return (ctypes.windll.user32.GetSystemMetrics(0) - PANEL_W) // 2

    def refresh_loop(self):
        while True:
            try:
                self.data = fetch_usage()
            except FileNotFoundError:
                self.data = "No credentials found. Log in via `claude` first."
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    self.data = "Rate limited (429). Retrying at the next poll."
                else:
                    self.data = f"API error ({e.code}). Reopen Claude Code to refresh."
            except Exception as e:  # noqa: BLE001 - any failure shows, loop lives on
                self.data = f"Fetch failed: {e}"
            # Sleep until the next poll, or until "r" wakes the loop early.
            self.refresh_now.wait(REFRESH_SECS)
            self.refresh_now.clear()

    def render(self):
        c, data = self.canvas, self.data
        self.drawn = data
        c.delete("all")
        if isinstance(data, str):
            c.create_text(
                PAD,
                PAD,
                text=data,
                fill=MUTED,
                font=FONT,
                anchor="nw",
                width=PANEL_W - 2 * PAD,
            )
            return
        bar_x0 = PAD + LABEL_W
        bar_x1 = PANEL_W - PAD - FIGURES_W
        for i, (key, label) in enumerate(LABELS.items()):
            block = data.get(key) or {}
            p = pct(block)
            dt = parse_reset(resets_at(block))
            y = PAD + i * ROW_H + ROW_H // 2  # vertical center of the row
            c.create_text(PAD, y, text=label, fill=FG, font=FONT_BOLD, anchor="w")
            c.create_rectangle(bar_x0, y - 2, bar_x1, y + 2, fill=TRACK, width=0)
            if p:
                fill_x = bar_x0 + (bar_x1 - bar_x0) * min(p, 100) / 100
                color = WARN if p >= 80 else ACCENT
                c.create_rectangle(bar_x0, y - 2, fill_x, y + 2, fill=color, width=0)
            shown = f"{p}%" if p is not None else "?%"
            c.create_text(
                PANEL_W - PAD,
                y,
                anchor="e",
                fill=MUTED,
                font=FONT,
                text=f"{shown}  ·  {format_abs(dt)} ({format_delta(dt)})",
            )

    def in_trigger_zone(self, x, y):
        # Small hot strip exactly over where the panel sits -- only
        # hovering *that* spot at the top edge reveals it.
        return self.x <= x <= self.x + PANEL_W and y <= EDGE_TRIGGER_PX

    def in_keep_zone(self, x, y):
        # Deliberately larger than the trigger zone (wider + taller) so
        # every trigger point is also a keep point -- prevents flicker.
        return (
            self.x - KEEP_PAD_X <= x <= self.x + PANEL_W + KEEP_PAD_X
            and y <= PANEL_H + HIDE_MARGIN_PX
        )

    def poll_cursor(self):
        # Always reschedule: one failed tick must not stop polling for good,
        # which would leave the panel stranded while the process lives on.
        try:
            self.tick()
        finally:
            self.root.after(POLL_MS, self.poll_cursor)

    def tick(self):
        pt = ctypes.wintypes.POINT()
        ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
        self.x = self.center_x()
        if not self.visible and self.in_trigger_zone(pt.x, pt.y):
            self.visible = True
            self.render()  # also refreshes the relative reset times
            # Win+D, explorer restarts and full-screen apps can minimize
            # the panel or drop it out of the topmost band; undo that.
            self.root.deiconify()
            self.root.attributes("-topmost", True)
            self.root.lift()
        elif self.visible and not self.in_keep_zone(pt.x, pt.y):
            self.visible = False
        if self.data is not self.drawn:
            self.render()
        if self.root.state() != "normal":
            self.root.deiconify()
        # Re-apply position whenever it drifts (Windows moves windows on
        # monitor/sleep changes), not only on show/hide transitions.
        y = self.shown_y if self.visible else self.hidden_y
        geom = f"{PANEL_W}x{PANEL_H}+{self.x}+{y}"
        if self.root.geometry() != geom:
            self.root.geometry(geom)

    def quit(self, event=None):
        self.root.destroy()
        os._exit(0)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    Widget().run()
