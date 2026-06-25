# Decision Log

### Entry 1

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Plan the "ultimate Claude Code monorepo" (claude-code-command-center).

**Context:** The user asked for an ultimate repo centered around Claude Code containing
utility tools, developer tools, apps, and libraries. Via AskUserQuestion they chose:
(1) a monorepo of real projects, (2) a written plan first, (3) the existing `reference/`
projects should become the actual content. Two forks needed resolving: (a) whether to
drive planning through the `plan-fullstack-app-*` skills, and (b) the top-level structure.

**Decision:**
- Did NOT use the `plan-fullstack-app-iteratively` / `-to-mvp` skills. Those are scoped to
  planning a single fullstack app's build (backend/frontend/db, iterations §01–§06). This
  task is consolidating five heterogeneous existing projects (Python, Node/VSCode, static
  web, PowerShell/Bash scripts) into one monorepo plus headroom to grow. A tailored,
  phased monorepo plan is the lower-process, better-fit artifact. Wrote it to
  `.agents_workspace/planning/SKELETON.md`.
- Proposed top-level structure grouped by category (`apps/`, `tools/`, `libs/`, `plugins/`)
  matching the user's own framing ("utility tools, developer tools, apps, library").

**Impact / Risk:** Low this session — planning only, no code moved, no project files touched.
The plan proposes `git mv` for relocation (preserves history) and leaves each subproject's
internal layout intact in the first phase.

**Outcome:** Plan written and presented to the user for approval before any relocation.

### Entry 2

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Phase 1 — relocate the five reference projects into the monorepo structure.

**Context:** User asked for "very clear and distinct" member names (a newcomer should know
what each is at a glance), said the `claude-automation` suite should be split because it
bundles multiple independent tools, chose a single Apache-2.0 license for the whole repo,
and confirmed all Python should use `uv`.

**Decision:**
- Renamed members to descriptive folder names (brand names stay inside each member's own
  README): vantage→`apps/cross-repo-file-diff`, docket→`apps/multi-repo-plan-runner`,
  plugin-toggler→`apps/per-project-plugin-toggler`; automation split into four `tools/`
  members (`statusline-cost-dashboard`, `session-name-date-prefixer`,
  `claude-md-devcontainer-sync`, `settings-devcontainer-sync`); scheduler→
  `tools/scheduled-automations`. Relocated with `git mv` (history preserved).
- Single root Apache-2.0 LICENSE; removed all per-member LICENSE files. This relicenses
  `scheduled-automations` (was MIT) and the VSCode extension (was MIT) to Apache-2.0;
  updated the extension's `package.json` `license` field to match — user explicitly chose
  "apache 2 only" and owns all the code.
- The automation suite's overview README moved to `docs/automation-suite.md` and its
  decision log to `docs/automation-suite-decision-log.md` so that context survives the split.
- "All Python uses uv" deferred to Phase 1b (separate commit) so the relocation commit
  touches no file internals (only the one license metadata field above).

**Impact / Risk:** Low. Renames preserve git history. The four split tools have no per-tool
README yet (the suite README covered them) — flagged as a Phase 2 follow-up.

**Outcome:** Relocation staged as 225 renames + 5 license deletions + root README/.gitignore.
