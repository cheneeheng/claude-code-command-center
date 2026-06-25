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

### Entry 3

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Phase 1b — adopt `uv` for all Python members.

**Context:** User confirmed "they should all use uv." Only `multi-repo-plan-runner` (docket)
had a pyproject. The two other Python members (`statusline-cost-dashboard`,
`per-project-plugin-toggler`) were stdlib-only with no project file. Open question from the
skeleton (§5.3): one root uv workspace vs independent uv projects.

**Decision:** Independent uv projects (each its own `pyproject.toml` + `uv.lock`), not a root
workspace yet. Reasons: minimal change, no shared deps to dedupe today, and the skeleton
defers a workspace to Phase 4 when `libs/` appears. Both new projects are `dependencies = []`
(stdlib) and `[tool.uv] package = false` (run as scripts, not installed). Dev tooling pinned:
ruff + mypy. Did NOT retrofit strict typing/lint fixes onto the existing code — that is a
separate follow-up, kept out of the uv-adoption change.

**Impact / Risk:** Low. No runtime deps added; lockfiles contain only dev tools. `.venv/` is
gitignored. Existing scripts still run unchanged via `uv run`.

**Outcome:** `uv lock` resolves in both members; `uv run` confirmed working.

### Entry 4

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Phase 3 — unified CI.

**Context:** Added a root GitHub Actions workflow. A ruff gate is only worth committing if it
starts green, but two members had violations, and some members already shipped their own
(now-inert) `.github/workflows/`.

**Decision:**
- Authored CI inline (one root `.github/workflows/ci.yml`) rather than spawning the
  github-actions agent — the user asked to continue, not to delegate. Jobs: `ruff` across the
  three Python members (matrix) + `pytest` for `multi-repo-plan-runner` (the only pytest suite;
  the toggler's tests are shell smoke tests). Uses `astral-sh/setup-uv` (uv provides Python).
- Made the two red members green by the least-invasive correct means, not by rewriting code:
  fixed 2 genuine empty-f-string smells in the dashboard server; excluded the abandoned
  `statusline.py` from ruff; and added `ignore = ["E701"]` to the toggler to respect its
  deliberate aligned compact style. Did not touch the toggler's or dashboard's logic.
- Left the members' pre-existing nested `.github/workflows/` in place. GitHub only runs
  workflows from the repo-root `.github/`, so they are inert (no duplicate runs); reconciling
  or removing them is a member-content follow-up, kept out of this change.
- Kept the uv-corrected `multi-repo-plan-runner/uv.lock` (it had a stale `1.0.0`; uv set it to
  the pyproject's `2.0.0`).

**Deferred (noted, not done):** per-member path-filtering (needs a filter action or split
workflows — not worth it at this size), SHA-pinning the actions (currently version tags),
mypy in CI (non-strict on untyped legacy code is low-signal), and PowerShell/Bash script
linting.

**Impact / Risk:** Low. Verified locally: all three members ruff-green; plan-runner pytest
194 passed, 100% coverage. CI starts green.

**Outcome:** The code changes (ruff-clean prep) pushed fine. The workflow file itself was
rejected on `git push` — this OAuth token lacks the `workflow` scope, so it cannot create
`.github/workflows/`. The validated `ci.yml` is held locally and needs to be added through a
path that has `workflow` scope (GitHub UI/API, or a token with the scope). Flagged to the user.
