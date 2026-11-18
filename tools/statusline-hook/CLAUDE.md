# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A public Claude Code statusline: one line (model, prompt cache countdown, context percentage,
5-hour and 7-day rate-limit percentages with reset countdowns, runtime, cost). Two single-file
ports:

- `statusline-hook.sh`: bash; one `jq` call pulls `transcript_path`, a second renders everything
  from the payload plus the transcript's last 100 lines.
- `statusline-hook.ps1`: Windows PowerShell 5.1 and PowerShell 7.

`statusline-hook-setup.ps1` and `statusline-hook-setup.sh` (needs `jq`) each install either one
into a Claude config dir and wire `statusLine`. Keep the two setup scripts behaving alike.

## Running / checking

```
bash tests/golden.sh bash statusline-hook.sh
bash tests/golden.sh pwsh -NoProfile -File statusline-hook.ps1
bash tests/golden.sh powershell -NoProfile -File statusline-hook.ps1
bash tests/smoke.sh
bash tests/export.sh bash statusline-hook.sh
bash tests/export.sh pwsh -NoProfile -File statusline-hook.ps1
bash tests/export.sh powershell -NoProfile -File statusline-hook.ps1
```

On a machine whose time zone isn't UTC, the PowerShell runs show reset-time differences only
(PowerShell ignores `TZ` on Windows). CI runs them in UTC.

## Invariants — do not break these

- **`fixtures/` is the spec, and both ports must produce the same bytes.** A behaviour change is a
  fixture change plus the same edit in both scripts, with the golden harness green for both.
- **The statusline only prints the statusline, except the quota export:** unless
  `C4_STATUSLINE_DISABLE_EXPORT` is on, it overwrites the one file
  `~/.claude/statusline/latest/rate-limits.jsonl`. No other file, no other state between turns.
  The export runs after printing and swallows every error, so it never changes the output bytes.
  Tests must never write the real file: `golden.sh` and `smoke.sh` set
  `C4_STATUSLINE_DISABLE_EXPORT=1`, and `export.sh` uses a temp home.
- **Bad input prints nothing and exits 0.** That covers invalid JSON, a non-object payload, and
  anything that throws.
- **Output is one `\n`-terminated line with no `\r`, on every OS.** The bash port strips the `\r` that
  jq writes on Windows, and the PowerShell port writes with `[Console]::Out.Write`.
- **`statusline-hook.ps1` stays ASCII-only.** PowerShell 5.1 reads a BOM-less script as ANSI, so
  glyphs are built from code points (`[char]0x21BA`).
- **`C4_STATUSLINE_NOW` is test-only.** It pins "now" (epoch seconds) so the time left until a
  reset is deterministic in the fixtures. Never document it as a user setting.
- **Dependencies:** bash needs only `jq`. PowerShell needs no modules.
- **`.gitattributes` pins LF** for scripts and fixtures. A CRLF checkout would break bash and the
  byte comparison.

## Conventions

- Version lives in `VERSION`; release tag `slh-vX.Y.Z` (see `docs/releasing.md`), changes in
  `CHANGELOG.md`.
- Also installable via the repo-wide `setup/` orchestrator
  (`command-center.ps1 install -Member statusline-hook`).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
