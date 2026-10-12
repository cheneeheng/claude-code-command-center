# v3 — Monorepo Docs Cleanup Plan

Status: active (this is the working record for the docs cleanup; it is intentionally
**not** removed by Phase 2, which only prunes the old v1/v2 build plans and per-member
planning artifacts).

## Goal

A single, consistent documentation surface across the monorepo:

- **One README per member** (apps/tools/libs/setup) + one root README.
- **All old planning artifacts removed** (SKELETON/ITER build specs, versioned variants).
- **Scattered agent decision logs consolidated** into one historical archive, with the
  repo-root active log kept for going-forward entries.
- **Consistent structure** and **refreshed content** across every README.

## Confirmed decisions (from scoping)

1. **Genuine user guides are kept.** The "one README" rule applies to `README.md` files
   only. `multi-repo-plan-runner/docs/guide/**` and
   `per-project-plugin-toggler/docs/user-guide-*.md` stay; the README is the entry point
   that links into them.
2. **`per-project-plugin-toggler/vscode-extension/README.md` is kept** as a documented
   exception — it is the README published with the VSIX and rendered on the VSCode
   marketplace page.
3. **Decision-log archive lives under `.agents_workspace/`** (next to the active log).
   The 5 scattered historical logs are archived; the root active log is preserved.
4. **This v3 plan is preserved** through Phase 2; only old v1/v2 planning is removed.

## End-state per member

`README.md` (single entry point) · `CHANGELOG.md` (kept) · `CLAUDE.md` (kept where
present, references fixed) · genuine user guides (kept) · code. No `planning/`, no
per-member `DECISION_LOG.md`.

## Phase 1 — Consolidate decision logs

Create **`.agents_workspace/archive/decision-log.md`**. Merge the following 5 historical
logs, each under a `## <source-member>` heading with a provenance line (original path)
and entries copied **verbatim**:

- `apps/cross-repo-file-diff/docs/claude_logs/DECISION_LOG.md` (45 lines)
- `apps/multi-repo-plan-runner/.agents_workspace/DECISION_LOG.md` (131 lines)
- `apps/per-project-plugin-toggler/docs/claude_logs/DECISION_LOG.md` (380 lines)
- `tools/scheduled-session-digests/docs/claude_logs/DECISION_LOG.md` (20 lines)
- `docs/automation-suite-decision-log.md`

Then `git rm` all five. **Keep** root `.agents_workspace/DECISION_LOG.md` as the active
going-forward log. **Keep** `scheduled-session-digests/docs/claude_logs/` directory +
`.gitkeep` — it is a runtime staging area (`LESSONS_LEARNED.md`); only its agent log leaves.

## Phase 2 — Remove planning artifacts

`git rm -r`:

- `.agents_workspace/planning/v1/`, `.agents_workspace/planning/v2/` (keep `v3/`)
- `apps/cross-repo-file-diff/docs/planning/` (includes `brand.css`)
- `apps/multi-repo-plan-runner/.agents_workspace/planning/`
- `apps/per-project-plugin-toggler/docs/planning/`

Plus stray `apps/multi-repo-plan-runner/experiment.md`.

**Preserved:** all *runtime* "planning" references (docket reads target repos'
`planning/` — product behavior, not our planning) and
`multi-repo-plan-runner/.agents_workspace/ARCHITECTURE.md` (living architecture doc).

## Phase 3 — Fix references to deleted docs

- Root `README.md` — build-plan / decision-log block → repoint to archive / remove.
- Root `CLAUDE.md` "Plan & decisions" → planning removed; point to active log + archive.
- `cross-repo-file-diff/CLAUDE.md` — cites `SKELETON_v3` / `ITER_*_v3` as design
  authority; fold essential current-design facts inline, drop planning pointers, repoint
  log to archive.
- `cross-repo-file-diff/README.md`, `multi-repo-plan-runner/CLAUDE.md`,
  `per-project-plugin-toggler/CLAUDE.md` — drop own-planning pointers.
- CHANGELOG entries mentioning `ITER_` / planning → **left verbatim** (frozen history).

## Phase 4 — One README per member

- `scheduled-session-digests`: fold the 4 sub-READMEs (`daily-summary`, `daily-lessons`,
  `weekly-lessons`, `git-sync`) into the top README as sections; update its subfolder
  links; `git rm` the 4. Operational prompt `.md` files + trigger scripts untouched.
- `per-project-plugin-toggler/vscode-extension/README.md`: **kept** (marketplace exception).
- All other members already have exactly one README.

## Phase 5 — Content refresh (quality)

Standardize every member README to a common template:
**Title + one-liner → What it does → Install/Setup → Usage → Configuration (C4_* env
vars) → Links (guides, CHANGELOG)**. Refresh root README into a clean member catalog by
category. Verify all internal links resolve.

## Phase 6 — Record conventions

Update root `CLAUDE.md` docs conventions: archive location, one-README rule, guide-tree +
VSCode-README exceptions. Add a `DECISION_LOG.md` entry for the cleanup.

## Preserved / out of scope

CHANGELOG files · member CLAUDE.md (refs only) · ARCHITECTURE.md · genuine user guides ·
operational prompt files · runtime `claude_logs/` staging · `.venv`.

## Mechanics

Branch `docs/cleanup`, commit per phase, left on the branch for end-of-work review
(no PR unless requested).
