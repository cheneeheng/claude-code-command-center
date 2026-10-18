---
status: fixed
date: 2026-10-18
plan: product/plans/usage-insights.md
---

# Switching between 7, 30, and 90 days leaves the dashboard looking unchanged

**Symptom:** clicking 7 days / 30 days / 90 days in the browser → the "This week", "This month",
"Pace", and "Month forecast by project" panels, which fill the first screen, show the same
figures for every range ("$166 forecast", "$162 so far" in all three).

## Diagnosis

| Hypothesis | Refuted by | Result |
| --- | --- | --- |
| The server ignores `range` | `aggregate.summary` returning different totals per range | refuted: 7d $158.13 / 64 sessions, 30d $780.67 / 535, 90d $2784.49 / 1294 (read-only script on the real store) |
| The served bundle is stale and does not send `range` | `range=` in the built JS | refuted: `api/summary?range=${e}` in `static/assets/index-*.js` |
| The request is slow, so old figures stay dimmed | each `/api/summary` answering within a second | refuted: 0.70 s, 0.72 s, 0.75 s, payloads 79 KB / 89 KB / 90 KB |
| The frontend drops the new payload | panels below the fold changing per range in the browser | refuted: Projects 29 → 37 → 44, Models 3 → 5 → 7, Top sessions 67 → 100 |
| The first section is range-independent by design | the plan saying otherwise | confirmed: plan Design "**Projection** (independent of the selected range)" and "`projection.pace` always holds the last 30 local days" |

**Cause:** `src/usage_insights/aggregate.py` (`_projection` over `PACE_DAYS = 14`, and
`PACE_STRIP_DAYS = 30`), as the plan specifies: everything in "What will I spend?" ignores the
range, and that section fills the first screen, so a range switch shows no visible change until
the reader scrolls. The health status chips also use fixed 30-day windows (`HEALTH_WINDOW_DAYS`).

**Prediction:** the week forecast is identical across ranges in the payload → `week 162.36` for
7d, 30d, 90d, and all, seen in the script output.

The fix is a design choice (which panels should follow the range), left to the user.

## Fix

The user chose to keep the projection range-independent and say so on screen. The section
layout gained an optional `note`, and "What will I spend?" shows "Based on the last 14 days,
not affected by the range." under its heading. "Based on" rather than "Last 14 days" because
the pace strip in the same section shows 30 days.

**Check:** `defaultLayout.test.tsx` "says the projection section does not follow the range",
red before the change, green after; `bun run test` 31 passed.
