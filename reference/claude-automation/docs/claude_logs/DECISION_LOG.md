### Entry 001

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-10T00:00:00+02:00
**Task:** Update dashboard.css to follow the styling in tmp.css

**Context:** tmp.css styles a different component set (plugin manager), so "follow the styling" could not mean copying rules 1:1. It also omits the Google Fonts @import (VSCode CSP) and lacks tokens the dashboard JS/markup depend on.
**Decision:** Adopted tmp.css's design language and foundation: radius token hierarchy (--radius-lg/md/sm), --shadow-sm as the only shadow, no atmosphere/glow/hover-lift, secondary-teal hover states, tmp.css's theme-btn and section-title styles. Kept the font @import (standalone HTML page), the semantic chart colors, the legacy alias layer, and --accent-hi (read by dashboard.js for chart hover). Skipped the VSCode bridge block (dashboard never runs in a webview).
**Impact / Risk:** Visual-only changes; cards lose hover lift and glow shadows, hovers shift from terracotta to teal. No markup or JS changes.
**Outcome:** dashboard.css rewritten; grep confirmed no remaining references to dropped tokens.

### Entry 002

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-16T00:00:00+02:00
**Task:** Refactor the dashboard server — separate the two data sources, add a README

**Context:** User chose "Restructure modules"; the option preview depicted a nested `dashboard/` package (session_stats.py, live_statusline.py, merge.py, README.md). But `dashboard_server.py` loads the static assets via `Path(__file__).parent / dashboard.html`, and the scheduled-task launcher runs `cc-statusline-dashboard-server.py` from this exact folder with sibling-module imports on sys.path. A nested package would force asset-path and import-path rewrites for no functional gain.
**Decision:** Kept the new modules flat in the existing folder rather than nesting them in a `dashboard/` subpackage. Split `dashboard_data.py` into `session_stats.py` (transcripts → tokens + estimated cost), `live_statusline.py` (statusline logs → rate limits + actual cost), and `merge.py` (reconciliation + payload). Moved `build_payload` out of `dashboard_server.py` into `merge.py`; deleted `dashboard_data.py`. The semantic outcome (three separated modules + README) matches the user's selection.
**Impact / Risk:** No behavior change except a ~1e-12 float-ordering difference in `by_model` cost (per-session grouping of the four cost terms instead of one streamed accumulator); invisible after 2-decimal formatting. Asset loading and launch path untouched.
**Outcome:** All modules byte-compile; payload output verified equal to the original for sessions and live data, and equal-to-rounding for stats, against real ~/.claude data.
