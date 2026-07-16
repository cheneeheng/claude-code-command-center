# git-sync

A pure shell utility — no LLM involved. Called by `daily-summary`,
`daily-lessons`, and `weekly-lessons` after Claude has written its output files.
It is the **only** writer of git history in `claude-meta`.

1. `git add -A` in `$C4_CLAUDE_META_DIR`.
2. Commits with message `<label>: <timestamp>` (e.g. `daily-summary: 2026-04-07 02:03`).
3. Pushes if a remote is configured; logs a note and exits cleanly if not.

It no-ops safely when there is nothing staged or the meta dir is not a git repo.

---

## Usage

```powershell
# Windows
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "daily-summary"
```

```bash
# Linux
bash "$C4_CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "daily-summary"
```

The label defaults to `auto` when omitted.

---

## Install

`git-sync` is copied automatically by any scheduler's installer
(`daily-summary`, `daily-lessons`, or `weekly-lessons`). To install it
standalone:

```powershell
# Windows
cd git-sync
.\install.ps1
```

```bash
# Linux
cd git-sync
bash install.sh
```

---

## Add a remote

```bash
cd "$C4_CLAUDE_META_DIR"
git remote add origin <your-remote-url>
git push -u origin main
```

The layout of the `claude-meta` repo itself is documented in the
[member README](../README.md#the-claude-meta-repo).
