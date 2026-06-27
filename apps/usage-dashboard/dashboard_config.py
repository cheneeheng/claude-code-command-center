"""Runtime configuration for the usage dashboard.

Transcript parsing and the model pricing table live in the `claude-usage` library;
this module only holds dashboard-specific runtime config. `CLAUDE_DIRS` may be
overridden at startup from the server's `--claude-dir` flag.
"""

import os
from pathlib import Path

import claude_usage

CLAUDE_DIRS: list[Path] = claude_usage.claude_dirs()

# Sessions with no statusline update in this window are considered inactive.
LIVE_SESSION_TIMEOUT_SECS: int = int(os.environ.get("STATUSLINE_LIVE_TIMEOUT", 1800))  # 30 min
