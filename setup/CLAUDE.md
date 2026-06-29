# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The unified installer for the repo's installable `tools/` members — umbrella infra, not a member
itself. One `command-center.ps1` entry point installs/uninstalls those tools and tracks state in a
per-machine manifest under `~/.claude-command-center/`. It is a **thin delegator**: it calls each
member's own setup script and never reimplements install logic.

## Running

See README.md for full usage. `./setup/command-center.ps1 <list|status|install|uninstall>` with
`-Member <name>` or `-All`; config at `~/.claude-command-center/config.json` (override with
`-Config`).

## Files

- `command-center.ps1` — the CLI (`list` / `status` / `install` / `uninstall`).
- `registry.ps1` — the catalog of managed members, one descriptor each.
- `command-center.config.example.jsonc` — config template.

## Invariants — do not break these

- **Never reimplement a member's install logic here.** Each descriptor's `Install`/`Uninstall`
  blocks delegate to that member's own setup script. This is what preserves the
  no-cross-member-dependency rule — only `setup/` knows all members, and it knows them only through
  delegation.
- **Add a member by appending a descriptor to `registry.ps1`** (its `SetupScript`,
  `Install`/`Uninstall` blocks, a `Detect` probe, and any `RequiredConfig` keys). Nothing else
  should need to change.
- **The manifest at `~/.claude-command-center/manifest.json` is the source of truth for uninstall.**
  `file-sync` and digest uninstalls **replay** the recorded params, so install must record exactly
  the params needed to reverse it. Do not break that replay contract.
- **`install -All` skips (with a note) any member missing required config** rather than failing.
  Preserve graceful skipping.
- **`status` compares manifest vs live detection** (PATH entry, `settings.json` key, scheduled
  tasks). Keep `Detect` probes accurate when adding/altering members.

## Conventions

- PowerShell; Windows Task Scheduler for the members that schedule jobs.
- Apps, `usage-report`, and libs are intentionally **not** managed here (run on demand, not
  installed).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
