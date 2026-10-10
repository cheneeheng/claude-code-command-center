# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A public Claude Code statusline: up to three aligned rows (model, context gauge, runtime, cost;
then 5-hour and 7-day rate-limit gauges with reset times). Two single-file ports:

- `statusline-hook.sh`: bash; renders everything in one `jq` program.
- `statusline-hook.ps1`: Windows PowerShell 5.1 and PowerShell 7.

`statusline-hook-setup.ps1` installs either one into a Claude config dir and wires `statusLine`.

## Running / checking

```
bash tests/golden.sh bash statusline-hook.sh
bash tests/golden.sh pwsh -NoProfile -File statusline-hook.ps1
bash tests/golden.sh powershell -NoProfile -File statusline-hook.ps1
bash tests/smoke.sh
```

On a machine whose time zone isn't UTC, the PowerShell runs show reset-time differences only
(PowerShell ignores `TZ` on Windows). CI runs them in UTC.

## Invariants — do not break these

- **`fixtures/` is the spec, and both ports must produce the same bytes.** A behaviour change is a
  fixture change plus the same edit in both scripts, with the golden harness green for both.
- **The statusline only prints the statusline.** No export, no files written, no state between
  turns. Data export belongs in a separate tool.
- **Bad input prints nothing and exits 0.** That covers invalid JSON, a non-object payload, and
  anything that throws.
- **Output is `\n`-terminated rows with no `\r`, on every OS.** The bash port strips the `\r` that
  jq writes on Windows, and the PowerShell port writes with `[Console]::Out.Write`.
- **Rows 2–3 start with U+2800 (Braille blank), not a space.** Claude Code trims leading
  whitespace from each row, which collapsed the alignment. U+2800 renders empty but isn't
  whitespace. The indent is U+2800 plus (model + effort width + 2) spaces.
- **`statusline-hook.ps1` stays ASCII-only.** PowerShell 5.1 reads a BOM-less script as ANSI, so
  glyphs are built from code points (`[char]0x2501`).
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
