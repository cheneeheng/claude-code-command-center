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

### Entry 5

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Split statusline-cost-dashboard into a tool + an app; define the app/tool boundary.

**Context:** User asked what distinguishes `apps/` from `tools/` and proposed splitting the
statusline member. Also asked that the dashboard read the statusline JSONL export only if
present and skip it otherwise.

**Decision:**
- Boundary recorded in root CLAUDE.md: an **app** is a destination you open and interact with
  via a UI (web page, TUI, dashboard, editor extension); a **tool** is plumbing invoked by
  something else (hook, scheduled task, CLI shim) with no interactive surface. Split members
  that bundle both.
- By that rule, split the member: hook scripts -> `tools/statusline-hook` (new minimal uv
  project); the dashboard server -> `apps/usage-dashboard` (kept the existing uv project,
  renamed `statusline-cost-dashboard` -> `usage-dashboard`). Folder-level `git mv` so the
  dashboard's internal bare-name / $PSScriptRoot references stay valid; internal filenames kept
  (per the "files keep original names" convention).
- The two halves share only a documented file contract (`~/.claude/statusline/<project>/
  <session>.jsonl`). Cross-linked both READMEs; flagged the schema as a future `libs/`
  candidate. Updated the catalog (README, CLAUDE.md), the parked CI matrix, and the suite doc.
- **Graceful skip was already implemented** end-to-end (`live_statusline._statusline_files`
  guards on dir existence; `read_statusline` returns an `_EMPTY` shape with `available: False`;
  `merge.build_payload` no-ops; `dashboard.js` shows "Hook not set up"). Per write-less-code I
  added no new logic — only fixed the now-cross-member UI hint text. Verified with an empty
  CLAUDE_DIR: payload returns `available: False`, no crash.

**Impact / Risk:** Low. Both new members ruff-green; dashboard imports resolve; graceful-skip
verified. History preserved via git mv.

### Entry 6

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Phase 4 — shared library, after validating (and correcting) its premise.

**Context:** User questioned whether extracting a lib would just be "a random utility lib file."
Investigation confirmed the skeleton's premise was false: only `usage-dashboard` parses
`~/.claude/projects/**/*.jsonl`. docket's "projects" are its own repo registry; the scheduler
is shell-based. So a transcript-parsing lib would have had a single consumer — a forced
abstraction.

**Decision:**
- Did NOT do a single-consumer extraction. Built a genuine **second consumer first**:
  `tools/usage-report` (a CLI counterpart to the dashboard). With two real consumers, the
  extraction is justified.
- Created `libs/claude-usage` as a proper library (hatchling src/ layout, `dependencies = []`,
  `py.typed`, strict mypy, public API + `__all__` in `__init__.py`). Domain: "read Claude Code
  local session data" (discovery + parsing + `Session` model + pricing/estimated cost) — a
  cohesive contract, not a utils drawer.
- Refactored `usage-dashboard` onto the lib: `session_stats.load_sessions()` is now a thin
  adapter (`asdict` of the lib's `Session`) so `merge.py`/server are untouched; `dashboard_config`
  drops the pricing table and sources `CLAUDE_DIRS` from the lib. Verified output **byte-for-byte
  identical** to a pre-refactor golden snapshot on a synthetic transcript.
- Wiring: per-consumer `[tool.uv.sources]` path deps (editable), **not** a root uv workspace —
  consistent with Entry 3 (independent projects), avoids entangling docket/toggler.
- Recorded the rule in CLAUDE.md: a `libs/` member needs a cohesive domain AND ≥2 consumers.

**Tradeoff accepted:** the dashboard previously ran as bare `python …py` (vendored, zero-dep);
it now depends on `claude-usage`, so the supported run is `uv run python …py`. Justified by the
repo-wide "all Python uses uv" mandate; READMEs/docstrings updated.

**Not done (flagged):** no unit tests for the lib/CLI (contract: tests only when requested) —
verified instead via the golden-snapshot diff. Tests are the obvious follow-up for a reusable lib.

**Impact / Risk:** Low–medium. Behavior verified identical; lib+CLI ruff+strict-mypy green.

### Entry 7

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** Phase 5 — flagship member + related-repo reference.

**Context:** User picked the "skill/plugin browser" flagship, deferred the `cc` launcher, asked
to reference a separate `agent-skills` repo, and required the scheduler's bundled skills stay
scheduler-only.

**Decision:**
- Built `apps/skill-browser` (classified an **app** per the boundary: a UI you browse). Stdlib
  web server + accessible single-page UI; reads `installed_plugins.json`, parses each plugin's
  `skills/*/SKILL.md` frontmatter, lists/searches them grouped by plugin, shows the body on click.
  Strict-typed; ruff + mypy green; endpoints verified (incl. 404s for bad/non-int ids).
- Security: the body endpoint takes a **bounds-checked integer index** into the server's own
  scan — no user-supplied paths, so no traversal; file paths are stripped from the list payload;
  binds to `127.0.0.1`; UI uses `textContent` only (no HTML injection).
- Did **not** move `tools/scheduled-automations/skills/` — they remain scheduler-only per the
  user. (Also means a future Phase 6 marketplace would not use them.)
- Referenced `cheneeheng/agent-skills` in the README "Related repositories" section — kept as a
  separate repo. Discovered it's the marketplace source feeding the skills the browser lists.
- Deferred the `cc` launcher candidate.

**Impact / Risk:** Low. New isolated member; no changes to other members. Single consumer of the
plugin-data parsing, so kept local (no premature lib per the libs/ rule).

### Entry 8

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-25T00:00:00Z
**Task:** De-duplicate plugin/skill reading between skill-browser and plugin-toggler.

**Context:** User noticed overlap. Investigation confirmed real duplication (SKILL.md frontmatter
parsing + skill enumeration) and that the two parsers had already drifted (toggler handles block
scalars, browser didn't). Scope handling was toggler-only — the browser was scope-agnostic. User
asked to make the browser scope-aware too (so all three implementations match), chose **Option B**
(no library), and asked to document the duplication as a cross-reference.

**Decision:**
- **No `libs/` extraction.** The toggler is deliberately stdlib/zero-dependency and ships a
  parallel Node implementation (vscode-extension), so a Python lib would only de-dupe 2 of 3
  copies while forcing a dependency on a zero-dep app. Shared surface is small. (If a 4th Python
  consumer appears, revisit `libs/claude-plugins`.)
- Made `skill-browser` **scope-aware**: ported the toggler's `normalise_path`,
  `load_installed_plugins` (local/project/user bucketing against the launch cwd) and the robust
  `parse_skill_frontmatter` (block + inline). Each skill now carries a `scope`; the UI shows a
  scope badge and search matches scope. This also **de-drifts** the parser.
- Dropped `skill-browser` to **non-strict mypy** so its copied JSON-reading logic stays parallel
  to the toggler's rather than diverging through annotations; removed it from the strict-mypy CI
  job (still ruff-linted).
- Registered the duplication in `docs/shared-plugin-logic.md` (the 3 copies, why copied not
  shared, known intentional differences) with `Cross-reference:` comments in each Python + the JS
  copy. Recorded the "intentional duplication" convention in CLAUDE.md.

**Impact / Risk:** Low. Toggler logic unchanged (only a comment added); browser verified (38
skills, scope=user, endpoints + traversal-safety intact). Behaviour parity is now a maintained
contract via the register, not an accident.

### Entry 9

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Refactor tools — generic devcontainer-sync setup, file renames, personal-data scan.

**Context:** User asked to (1) scan the repo for accidental personal details, (2) make
`claude-md-devcontainer-sync` and (3) `settings-devcontainer-sync` generic so the two folders to
sync are passed as setup arguments, and (4) rename files in every tool except `usage-report` and
`scheduled-automations` to follow the tool's folder name.

**Decision:**
- Renamed files in `claude-md-devcontainer-sync`, `settings-devcontainer-sync`,
  `session-name-date-prefixer`, and `statusline-hook` to `<folder-name>[-suffix].<ext>` via
  `git mv` (history preserved). Updated internal references (setup -> core script, self-reference
  comments, per-tool READMEs).
- Made both sync setups take `-FolderA`/`-FolderB` (required on install); the generated VBS now
  embeds the resolved `<Folder>\<fixed-filename>` paths (`CLAUDE.md` / `settings.json`) instead of
  hard-coding `~/.claude` and `~/.claude_devcontainer`.
- **Left `docs/automation-suite.md` and `docs/automation-suite-decision-log.md` untouched.** They
  are an explicit historical snapshot of the original combined `claude-automation` suite (linked
  from the root README as "the combined overview" of the pre-split structure); rewriting filenames
  there would falsify the snapshot. Updated only live docs (per-tool READMEs + one accurate
  cross-reference in `usage-dashboard/README.md`).
- **Personal-data scan:** the tools are clean (they use `%USERPROFILE%`/`$HOME` or `C:\Path\To`
  placeholders). Real personal details exist elsewhere and were NOT auto-edited (out of the tools
  scope; reported to the user instead): real username paths `C:\Users\Chen\...` in
  `apps/per-project-plugin-toggler` (README + planning/decision docs) and `/Users/eeheng/...` plus
  "EeHeng" in `apps/cross-repo-file-diff/docs/planning`. The `cheneeheng` GitHub handle is a public
  intentional reference (per Entry 7), not accidental leakage.

**Impact / Risk:** Low-medium. Renames could break a user's existing install that points at old
script paths (sync tools regenerate their VBS on next install/uninstall; statusline users must
re-point their settings.json). No behavior change beyond the new required setup args.

---

### Entry 10

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Scrub personal-data leaks; drop "devcontainer" from the two sync tools' names.

**Context:** Follow-up to Entry 9. User asked to (1) fix the personal-data leaks that the Entry 9
scan reported but did not auto-edit, and (2) rename the sync tools so they no longer use
"devcontainer".

**Decision:**
- **Personal data:** replaced real-username local paths and the real name in committed/deliverable
  docs with placeholders — `C:\Users\Chen\...` -> `C:\Users\user\...` (ASCII-box alignment
  preserved by matching the 4-char width), `/Users/eeheng/...` -> `/Users/you/...`, "EeHeng's
  requirement" -> "the user's requirement", and the git user name `EeHeng Chen` -> the public
  handle `cheneeheng` alone in `per-project-plugin-toggler/docs/claude_logs/DECISION_LOG.md`.
  Touched: `per-project-plugin-toggler` README + `docs/planning/ITER_03.md` + that member log, and
  `cross-repo-file-diff/docs/planning/ITER_02_v2.md`, `ITER_02_v3.md`, `ITER_04_v3.md`.
- **Left the `cheneeheng` GitHub handle** everywhere it appears (READMEs, CHANGELOG links,
  package.json, schema `$id`) — intentional public reference per Entry 7, not leakage.
- **Left this `.agents_workspace/DECISION_LOG.md`'s Entry 9 finding text untouched** even though it
  quotes the leaked strings: it is the agent audit trail documenting the finding in past tense;
  editing it to remove the very example it records would falsify the log (same frozen-record
  principle applied to the automation-suite snapshot in Entry 9). Flagged to the user.
- **Sync-tool rename:** user chose to drop the qualifier entirely (over `folder-sync`/`mirror`).
  `claude-md-devcontainer-sync` -> `claude-md-sync`, `settings-devcontainer-sync` -> `settings-sync`,
  with the same drop applied to every script/VBS filename inside. README/setup example paths
  `.claude_devcontainer` -> `.claude_mirror` so the docs no longer reference devcontainer at all.
  Updated the umbrella catalog (root `README.md` + `CLAUDE.md`). `git mv` for the tracked READMEs;
  the three scripts per folder were already-untracked Entry 9 renames, moved with plain `mv`.
- **Scope:** left `.claude_devcontainer` references in `scheduled-automations` and `usage-dashboard`
  alone — there it is a real second Claude data directory those tools scan/serve, not a reference
  to the renamed sync tools (scope discipline: do not retrofit unrelated members).

**Impact / Risk:** Low. Doc/placeholder edits and a name change. Existing sync installs pointing at
the old folder/script paths must be reinstalled (they regenerate their VBS on next install).
PowerShell parse-check passes on all four renamed `.ps1` scripts.

---

### Entry 11

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Parameterize the sync tools' Task Scheduler folder/name so multiple syncs run in parallel.

**Context:** Both sync setups hardcoded `$taskFolder = "\ClaudeAutomation\"` and a single
`$taskName` (`SyncClaudeMd` / `SyncClaudeSettings`), plus a single fixed VBS launcher filename. That
caps each tool at one install — a second install overwrites the task and the launcher. User wants
the task folder derived from the tool folder name and the task name derived from the input args, to
sync several folder pairs at once.

**Decision:**
- **Task folder = tool folder name** via `Split-Path -Leaf $PSScriptRoot` (`\claude-md-sync\` /
  `\settings-sync\`). Register-ScheduledTask auto-creates the folder, same as the old hardcode.
- **Task name = stable identity derived from the folder pair**: `<leafA>-<leafB>-<8-char md5>` of
  the two resolved file paths. Chose readable leaf slugs + a hash (not leaves alone) because two
  different pairs can share leaf names (e.g. both `.claude`) and would otherwise collide. The
  launcher VBS is renamed the same way (`<tool>-<hash>-hidden.vbs`) — **required**, not cosmetic:
  parallel tasks each need their own launcher with their own embedded paths, or the last install
  clobbers the rest.
- **Order-independent identity:** sort the pair before hashing so `(A,B)` and `(B,A)` map to one
  task (sync is symmetric/newer-wins, so a reversed reinstall should not create a duplicate).
- **Uninstall now also requires `-FolderA`/`-FolderB`** — it must recompute the same identity to
  find the right task + launcher. Documented in usage + READMEs.
- **`[IO.Path]::Combine` + `GetFullPath`, not `Join-Path`/`Resolve-Path`:** identity must be
  computable on uninstall even if a folder/drive is gone; `Join-Path` and `Resolve-Path` hit the PS
  provider and throw on a missing drive. Combine/GetFullPath are pure-string .NET.
- **Gitignored the generated `*-<hash>-hidden.vbs` launchers** (they embed real local paths — the
  same leak class addressed in Entry 10) while keeping the committed `*-hidden.vbs` template (safe
  `C:\Path\To` placeholders, doc only); fixed the template header to say so.

**Impact / Risk:** Low-medium. Behavior change: uninstall signature now needs the folder pair, and
existing single installs under `\ClaudeAutomation\` are orphaned by the new task path — users should
uninstall via the old script revision or remove those tasks manually, then reinstall. Identity logic
verified in isolation (order-independence holds; distinct pairs differ; no error on missing drives);
both setup scripts parse-check clean. Not run end-to-end (needs Administrator + Task Scheduler).

---

### Entry 12

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Rename the `scheduled-automations` member to a self-descriptive name.

**Context:** User found `scheduled-automations` unclear ("not clear what it is doing"). The member
is one cohesive suite: scheduled, unattended Claude Code runs that read the user's own session
transcripts and produce daily summaries + daily/weekly lessons into the shared `claude-meta` repo.

**Decision:**
- Renamed `tools/scheduled-automations` -> `tools/scheduled-session-digests` (user chose from
  three candidates; noun-led form to match siblings like `cross-repo-file-diff`/`usage-report`).
  Used `git mv` (history preserved). Updated the two catalog references (root `README.md` table row
  + `CLAUDE.md` member list).
- **Did not edit the DECISION_LOG entries** (9, 10, 11) that reference the old name: they are
  past-tense audit records of work done under the old name — same frozen-record principle as
  Entries 10/11.
- **Did not rename the internal `claude-code-scheduler` branding** (README title, skill names
  `claude-code-scheduler-*`, task names `ClaudeCode-*`) — out of scope for a folder rename, and
  those names were already independent of the folder name. Flagged to the user.

**Impact / Risk:** Low. Folder rename + two doc edits; no script logic touched. Existing installs
are unaffected (they reference `CLAUDE_META_DIR` and installed copies, not the source folder path).

---

### Entry 13

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Align the internal `claude-code-scheduler` branding to the new folder name (follow-up to Entry 12, user said "Align please").

**Context:** After the Entry 12 folder rename, the member still used `claude-code-scheduler`
internally for its product title, the three interactive skill names/dirs, and its Windows Task
Scheduler folder + task names.

**Decision (naming scheme):**
- Product/title `claude-code-scheduler` -> `scheduled-session-digests` (matches the folder).
- Skill slash-commands `/claude-code-scheduler-<x>` -> `/session-digest-<x>` (dirs `git mv`'d,
  `name:` frontmatter updated). Chose the shorter `session-digest-` stem over the full folder name
  for usable slash commands; same recognizable stem, not a third unrelated variant.
- Task Scheduler folder `\ClaudeCodeScheduler\` -> `\ScheduledSessionDigests\`; task names
  `ClaudeCode-{DailySummary,DailyLessons,WeeklyLessons}` -> `SessionDigest-...`.
- Applied via `sed` across the 15 live files (install/setup scripts `.ps1`+`.sh`, READMEs, the 3
  `SKILL.md`). **Left `CHANGELOG.md` untouched** — its old-name references sit in dated historical
  version entries (frozen record, same principle as the DECISION_LOG entries). A new changelog entry
  documenting this rename should be added at the next release (flagged, not done — release flow owns it).

**Impact / Risk:** Medium for existing installs. The Task Scheduler folder/name and skill names
changed, so prior installs are orphaned under the old identifiers and must be uninstalled + reinstalled
(consistent with the Entry 11 orphaning note). All four edited `.ps1` scripts parse-check clean; not
run end-to-end (needs Administrator + Task Scheduler). No `.sh` shellcheck run.

---

### Entry 14

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Merge `claude-md-sync` + `settings-sync` into one `file-sync` member (user approved the spec).

**Context:** The two members' `*-setup.ps1` were byte-identical except the filename and the launched
script name; the two sync scripts differed only in the apply step (raw copy vs JSON-merge-with-excludes).
User pictured "a generic sync + 2 tools that inherit from it."

**Decision:**
- **One self-contained member, not two members + a shared base.** PowerShell has no inheritance, and
  this repo forbids cross-member dependencies (the same rule that kept the digests suite together).
  So "base + 2 subclasses" is realized as one `file-sync/` member: a generic engine + two thin
  wrapper entry scripts (composition, not inheritance). Rejected (a) two members importing a third
  base (cross-member dep) and (b) intentional duplication via `shared-plugin-logic.md` (preserves the
  duplication the merge removes).
- **Base = `sync-engine.ps1`** (`-Strategy raw|json-merge`, newer-wins selection shared, apply step
  branches) + **`sync-setup.ps1`** (generic Task Scheduler install, adds `-FileName`/`-Strategy`/
  `-ExcludePaths`). **Subclasses = `claude-md-sync-setup.ps1`** (raw, CLAUDE.md) and
  **`settings-sync-setup.ps1`** (json-merge, settings.json) — familiar command names preserved.
- **`-ExcludePaths` is now a comma-separated string** (was `[string[]]`) so it embeds cleanly in the
  generated VBS command line.
- **Task-identity (Entry 11) kept**, now under one `\file-sync\` task folder; added the file stem to
  the human slug so two files sharing a folder pair stay legible (hash already disambiguated them).
- **History:** `git mv settings-sync -> file-sync` (richer JSON logic = better base), renamed files in
  place, `git rm` the redundant `claude-md-sync` (its raw copy became the engine's `raw` branch).
  Updated root README + CLAUDE.md catalog (two rows -> one) and the `.gitignore` launcher pattern.
  Left the README "originally one claude-automation suite" note (past tense, accurate history).

**Impact / Risk:** Medium for existing installs — old tasks under `\claude-md-sync\` / `\settings-sync\`
are orphaned by the new `\file-sync\` task folder; users uninstall via the old scripts (or remove tasks
manually) then reinstall (Entry 11 precedent). Engine verified functionally on throwaway files: raw
newer-wins copy works; json-merge writes the newer file to the destination while preserving the
destination's excluded `statusLine.command`. All four `.ps1` parse-check clean. Not run end-to-end
through Task Scheduler (needs Administrator).

### Entry 15

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27T00:00:00Z
**Task:** Add a unified install/uninstall orchestrator + manifest for the installable `tools/` members.

**Context:** Each installable tool shipped its own setup script with a different interface, and
`statusline-hook` had none (manual `settings.json` edit). No single place installed everything and
nothing recorded what was installed on a machine. User confirmed: scope = installable `tools/` only;
write the missing/non-interactive scripts so `install -All` runs unattended; manifest in the home dir.

**Decision:**
- **New umbrella dir `setup/`, not a member.** The orchestrator spans members (it is not an app/tool/lib),
  so it is umbrella infrastructure: `setup/command-center.ps1` (CLI) + `setup/registry.ps1` (catalog) +
  config template, documented in the root README. Rejected making it a `tools/` member (it would import/
  drive sibling members, which the repo's no-cross-member-dependency rule forbids for members).
- **Thin delegator, never reimplements install logic.** Each registry descriptor's Install/Uninstall
  blocks call the member's own setup script; the orchestrator only sequences and records. One source of
  truth per member preserved.
- **Manifest stores the params used**, not just a boolean — `file-sync`/digest uninstall *replay* recorded
  params (file-sync uninstall needs the same folder pair it was installed with). State lives at
  `~/.claude-command-center/{manifest,config}.json` (per-machine, survives repo moves; not committed).
- **`status` verifies reality, not just the manifest** via per-member Detect probes (PATH entry,
  `settings.json` key, scheduled tasks) — surfaces hand-installed tools (yellow) and drift (red).
- **Config-file approach for unattended `file-sync`.** `file-sync` has no sensible default folder pair,
  so it is the only member with `RequiredConfig`; `install -All` skips it (with a note) when config is
  absent. `statusline-hook` (variant) and digests (metaDir/picks) have defaults, so they need no config.
- **Per-member changes:** new `statusline-hook-setup.ps1` (copies hook + sets `statusLine` via
  ConvertFrom/To-Json, preserving other keys); added a `-NonInteractive -MetaDir -Picks` path to the
  digests `setup.ps1` (interactive menu stays the default). `file-sync` already non-interactive — no change.
- **Skipped the planned `.gitignore` `setup/*.local.*` guard** (YAGNI): live config/manifest are in the
  home dir, so no in-repo file needs ignoring.

**Impact / Risk:** Low. All five `.ps1` parse-check clean; `list` and `status` run correctly and already
detect the user's hand-installed tools against an empty manifest. Actual install/uninstall (state-changing,
Task Scheduler, needs Administrator for some) not executed — verify with `install -Member <name>` then
`status`.
### Entry 16

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-27
**Task:** Prefix repo-owned env vars with C4_ across tools/ and setup/.

**Context:** Two matched files were historical records — `scheduled-session-digests/CHANGELOG.md`
and `docs/claude_logs/DECISION_LOG.md`. Renaming the env-var tokens inside them would rewrite
history. The user asked to update tools/setup code + CLAUDE.md + README, not history.
**Decision:** Excluded both historical files from the rename; renamed only live code, docs
(SKILL.md/README.md/.md task defs), and config across tools/ and setup/. Vars: CLAUDE_DIR ->
C4_CLAUDE_DIR, CLAUDE_META_DIR -> C4_CLAUDE_META_DIR, STATUSLINE_EXPORT -> C4_STATUSLINE_EXPORT
(prefix-the-full-name style, per user). OS vars (USERPROFILE/LOCALAPPDATA/PATH) left untouched.
**Impact / Risk:** Breaking change for existing installs that set the old var names; existing
persisted user env vars / scheduler.env entries must be re-set. No backward-compat shim added
(per contract). Other categories (apps/, libs/) intentionally not touched yet.
**Outcome:** All edited PowerShell/Bash/Python files pass parse/syntax checks; no bare tokens or
double-prefixes remain outside the two historical files.

### Entry 17

**Type:** Decision
**Mode:** Interactive (user-confirmed)
**Timestamp:** 2026-06-28
**Task:** Refactor apps: share the skills/agents/hooks parser between skill-browser and per-project-plugin-toggler; extend skill-browser to browse agents and hooks.

**Context:** skill-browser only read skills; the agents/hooks readers already existed (by intentional copy) in plugin-toggler. Adding agents+hooks to skill-browser triggers the register's documented "logic grows materially" / "2nd Python consumer" condition for extracting a library. Sharing model was a high-stakes fork (extract lib vs. expand duplication).
**Decision:** User chose extraction. Created libs/claude-plugins (stdlib-only, strict mypy) with normalise_path, plugins_base, load_installed_plugins, parse_frontmatter, load_plugin_skills/agents/hooks (skills/agents -> PluginMember incl. server-side path; hooks -> PluginHook). skill-browser and plugin-toggler/html import it; the VSCode extension.js stays a registered Node copy. Kept CLAUDE_DIR (not C4_) env var to match claude-usage and per Entry 16 (apps/libs left un-prefixed).
**Impact / Risk:** plugin-toggler/html gains an editable workspace dependency (no longer a single copy-paste file) and now: (a) returns empty buckets instead of raising on a malformed installed_plugins.json (lib catches JSONDecodeError); mock fallback on a *missing* file is preserved. VSCode Node copy unchanged. Behavior of skill-browser's existing skill reads unchanged.
**Outcome:** Pending validation (ruff + mypy + import smoke).

### Entry 18

**Type:** Decision
**Mode:** Interactive (user-confirmed name) + Autonomous (CSS scope)
**Timestamp:** 2026-06-28
**Task:** Rename skill-browser -> plugin-component-browser; reuse the toggler's styles.css.

**Context:** The app now browses skills/agents/hooks, so "skill-browser" was too narrow. User picked the name plugin-component-browser. "Reuse the toggler's styles.css, adapt as needed" left the adaptation scope to me; the toggler's CSS is a full theme with VSCode-bridge, theme-toggle blocks, toggler-only component classes, and a remote Google Fonts <link>.
**Decision:** Renamed via git mv (history preserved) and updated all non-historical references (pyproject, both READMEs, root README/CLAUDE.md, register, lib README/__init__, extension.js cross-ref). Created apps/plugin-component-browser/styles.css as a trimmed copy: kept the Tidewater token palette + base typography + light/auto-dark, dropped the VSCode bridge, [data-theme] toggle blocks, and all toggler-only classes; re-skinned this app's two-pane layout with the tokens. Added kind-badge tokens (skill/agent/hook) for theme-aware contrast. Skipped the remote Google Fonts link (system-font fallbacks) to keep this localhost, stdlib, offline tool dependency-free. Inline <style> in index.html replaced by a linked /styles.css served via a new server route.
**Impact / Risk:** Low. Fonts differ from the toggler (system fallbacks vs Fraunces/Hanken/JetBrains) — upgrade path is to add the same <link> if exact font parity is wanted. DECISION_LOG history entries left referencing the old name on purpose.
**Outcome:** ruff + mypy strict clean; smoke confirms /styles.css and /api/members resolve and the index loads.

### Entry 19

**Type:** Decision
**Mode:** Interactive (user-confirmed)
**Timestamp:** 2026-06-28
**Task:** Extend libs/claude-plugins to discover loose (non-plugin) skills/agents and surface them in the browser with loose-over-plugin precedence.

**Context:** The library read only installed plugins (installed_plugins.json). The user wanted the browser/toggler to also show locally-created and per-project skills that live directly under a .claude dir, not in a plugin. Two forks: (a) how much to put in the library vs the consumer, (b) precedence on name collisions, (c) whether the toggler should also gain a loose-component surface.
**Decision:** Added only discovery to the library — claude_dir() (extracted from plugins_base) and loose_bases(project_root) -> {user: <claude_dir>, project: <root>/.claude}. The existing member readers (load_plugin_skills/agents) already accept any base, so no new reader. Precedence/shadow logic stays in the browser (single consumer in v1, per the repo's "extract on the second consumer" rule). Precedence (user-confirmed): project-loose > user-loose > plugin; collisions are marked shadowed, not hidden (read-only viewer shows the full picture). Scope limited to skills + agents; loose hooks (settings.json) and commands deferred as a separate feature. Toggler NOT extended to toggle loose components — Claude Code has no native per-project on/off for loose skills, and faking one by mutating authored/committed files is out of scope; the toggler keeps toggling plugins only.
**Impact / Risk:** Low. Library gains two pure path helpers (stdlib, strict mypy clean). Browser Member gains source/shadowed fields; /api/members now emits them. Node copy (extension.js) intentionally NOT given loose discovery — registered as Python-only in docs/shared-plugin-logic.md to avoid being read as drift.
**Outcome:** ruff + mypy strict clean on lib and app; smoke test confirms loose discovery and that a project-loose skill shadows the same-named user-loose skill.

### Entry 20

**Type:** Decision
**Mode:** Interactive (user-confirmed name)
**Timestamp:** 2026-06-28
**Task:** Rename apps/plugin-component-browser -> apps/claude-component-browser.

**Context:** The app now browses plugin AND loose components, so "plugin-component-browser" undersold it; "component-browser" alone was judged not self-evident. User chose claude-component-browser. The toggler was intentionally NOT renamed (it only toggles plugins — name stays accurate).
**Decision:** Moved the folder (git tracked all files as renames; the app .venv was deleted and re-synced because moving it left stale absolute paths in its trampoline scripts). Updated all non-historical references: pyproject name + uv.lock (regenerated via uv lock), app README (also refreshed to describe loose components), server.py prog, root README + CLAUDE.md catalog, docs/shared-plugin-logic.md, libs/claude-plugins README + __init__ docstring, ci.yml ruff+mypy matrices, and the extension.js cross-ref comment. DECISION_LOG history entries left referencing the old name on purpose.
**Impact / Risk:** Low/mechanical. CI matrix paths updated so lint+typecheck still target the member. No public Python import path changed (the package dir libs/claude_plugins is unchanged; only the app folder moved).
**Outcome:** ruff + mypy strict clean from the new path; smoke test passes from the renamed dir.

### Entry 21

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** Rename usage-dashboard files to match the folder name; register the app in setup/registry.ps1.

**Context:** "Files follow the folder name" was unscoped. Three files carried the legacy
`cc-statusline-dashboard-server*` prefix; the internal modules (session_stats.py, merge.py,
dashboard_*.py/css/js) are already descriptive. The scheduled task name and two history docs
also reference the old names. registry.ps1 was documented as a tools/-only catalog.
**Decision:** Renamed only the three legacy-prefixed files (`usage-dashboard.py`,
`usage-dashboard-setup.ps1`, `usage-dashboard-start-once.ps1`) via `git mv`; left the
descriptive internal modules untouched. Left the scheduled task name `StartStatuslineServer`
unchanged (renaming it changes installed-task identity for existing users — out of scope).
Left `docs/automation-suite.md` and `docs/automation-suite-decision-log.md` unchanged — both
explicitly document the pre-split historical module, so editing them would falsify history.
Extended registry.ps1 to cover an `apps/` member (Category 'apps') rather than restricting it
to tools/; the orchestrator iterates descriptors generically, so this is safe.
**Impact / Risk:** Existing installs created under the old task name still resolve (task name
unchanged). Detect uses that task name. No functional change to the server.
**Outcome:** Files renamed, refs updated, PS/py parse-checks pass, registry loads and resolves
the new descriptor (Version 0.1.0).

### Entry 22

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** Monorepo-wide docs cleanup (v3 plan): one README per member, remove planning, consolidate decision logs.

**Context:** Several forks the user did not fully specify. (a) Where the consolidated archive
should live and whether to fold the active root log into it. (b) What to do with genuine
end-user guides (multi-repo-plan-runner `docs/guide/`, toggler `docs/user-guide-*.md`) under a
strict "one README" rule. (c) Whether to preserve the v3 cleanup plan itself given the "remove
all planning" instruction. (d) How hard to push the "improve content quality" goal against
already-strong member READMEs. (e) usage-dashboard / claude-component-browser / claude-usage read
the unprefixed `CLAUDE_DIR` env var, contradicting the repo's `C4_` convention.
**Decision:** (a) Built one frozen archive at `.agents_workspace/archive/decision-log.md` from the
5 scattered historical logs (4 member logs + the automation-suite log), entries verbatim under
per-source sections; kept the repo-root `.agents_workspace/DECISION_LOG.md` as the active
going-forward log (user choice). (b) Kept the guide trees as the deeper docs; "one README" applies
to `README.md` files only, with the README as the entry point that links in (user choice). Folded
scheduled-session-digests' 4 sub-READMEs into its top README; kept the VSCode-extension README as
the documented marketplace exception (user choice). (c) Preserved `.agents_workspace/planning/v3/`
(this plan) while deleting v1/v2 and all per-member planning — removing the active plan record
mid-task would be self-defeating. (d) Chose targeted quality fixes (dedupe, missing catalog entry,
CHANGELOG links) over a rigid-template rewrite, because the existing READMEs are already high
quality and homogenizing would reduce quality — flagged to the user with an offer to go deeper.
(e) Left the `CLAUDE_DIR` vs `C4_CLAUDE_DIR` mismatch untouched — it is a code/convention change
outside a docs cleanup; flagged to the user as a follow-up.
**Impact / Risk:** Low. ~60 files removed (recoverable from git history); references repointed;
all internal markdown file links verified to resolve. Frozen CHANGELOG and DECISION_LOG history
that names the deleted files was intentionally left verbatim, so a few historical references now
point at archived/removed paths by design.
**Outcome:** Work done on branch `docs/cleanup`, committed per phase, left for end-of-work review.

### Entry 23

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** Apply the `C4_` env-var prefix the repo convention requires (the follow-up Entry 22 deferred).

**Context:** Three env vars were read unprefixed, contradicting the repo rule that every var it
defines is `C4_`-prefixed: `CLAUDE_DIR` (read by `claude-usage` and `claude-plugins`) and
`STATUSLINE_LIVE_TIMEOUT` (read by `usage-dashboard`). This reverses Entry 22's "left untouched"
call now that the user has asked for the fix. Entry 16 / Entry (claude-plugins extraction) had
earlier kept `CLAUDE_DIR` unprefixed on purpose to match `claude-usage`; that rationale is now
superseded.
**Decision:** Renamed the env-var keys directly — `CLAUDE_DIR` → `C4_CLAUDE_DIR`,
`STATUSLINE_LIVE_TIMEOUT` → `C4_STATUSLINE_LIVE_TIMEOUT` — in the three reads plus their
docstrings and READMEs, and added `C4_STATUSLINE_LIVE_TIMEOUT` to the canonical lists in the
root CLAUDE.md and README. No backward-compatibility fallback (per the no-shims convention).
Left the Python module identifier `dashboard_config.CLAUDE_DIRS` unchanged — it is a code symbol,
not an env var. Frozen history (CHANGELOG, prior DECISION_LOG entries) naming the old vars is
left verbatim.
**Impact / Risk:** Breaking for anyone who currently sets `CLAUDE_DIR` / `STATUSLINE_LIVE_TIMEOUT`
for these members — they must switch to the `C4_`-prefixed names. `statusline-hook` and
`usage-report` already used `C4_CLAUDE_DIR`, so the suite is now consistent.
**Outcome:** No unprefixed env-var reads remain (grep clean); `py_compile` passes on the three
changed modules.

### Entry 24

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** PR #9 follow-up — reverse several PR #9 docs decisions per user instruction (restore
root planning v1/v2, drop per-member CHANGELOGs, archive the stray ARCHITECTURE doc, merge
per-member CI into root, restore the scheduled-session-digests sub-READMEs).

**Context:** The user flagged five mistakes from PR #9. Three required judgment calls beyond a
literal restore: (a) where to put the moved `multi-repo-plan-runner/.agents_workspace/ARCHITECTURE.md`
in the shared root archive, (b) how to fold per-member CI into the root workflow given GitHub only
runs `.github/workflows` at the repo root (the per-member workflows never executed), and (c) what to
do with two release-coupled pieces — pppt's `version-tag` CI job and its `release.yml`.
**Decision:**
- **Planning v1/v2** restored from `c823f0b~1`; v3 left in place. Frozen v1/v2/v3 SKELETONs that
  name the old CHANGELOG/ARCHITECTURE paths are left verbatim (frozen-history rule).
- **CHANGELOGs** all four deleted; no root changelog created yet (none until the repo's first
  release). README/CLAUDE.md/README catalog references to per-member CHANGELOGs removed, and the
  one-README convention amended to state members carry no `CHANGELOG.md`.
- **ARCHITECTURE** moved (via `git mv`) to `.agents_workspace/archive/multi-repo-plan-runner-architecture.md`
  — name-prefixed by source member to stay unambiguous in the shared archive, mirroring the
  consolidated `decision-log.md` convention. The nested `apps/multi-repo-plan-runner/.agents_workspace/`
  removed so only a root-level workspace remains; the three mrpr CLAUDE.md references repointed.
- **CI** merged into root `.github/workflows/ci.yml`: mrpr's stricter gates (`ruff format --check`,
  `pytest --cov-fail-under=100`, `docket init --dry-run` smoke) folded into the existing mrpr `test`
  job; pppt's five functional jobs (python-syntax, css-sync, lint-extension, package-check,
  smoke-test) ported with `apps/per-project-plugin-toggler/`-prefixed paths. Both per-member
  `ci.yml` deleted; mrpr's now-empty `.github` removed.
- **OMITTED pppt `version-tag`** job: it only fires on a tag push (root CI has no tag trigger) and
  asserts the release tag equals `vscode-extension/package.json` — incompatible with the planned
  single repo-root release where a tag like `v0.1.0` is not the extension version. Porting it
  would fail root releases. Left `apps/per-project-plugin-toggler/.github/workflows/release.yml`
  in place (it is a release workflow, not CI, and is out of the "merge CI" scope).
- **scheduled-session-digests sub-READMEs** restored from `db1cd2e~1` (top README reverted to its
  pre-consolidation, sub-folder-linking form); one-README convention amended to sanction these
  four sub-READMEs alongside the existing vscode-extension exception.
**Impact / Risk:** `version-tag` and `release.yml` are both currently inert (neither runs from a
subdir / without a tag trigger) — the VSCode extension's release automation is non-functional in
the monorepo and needs a deliberate root-level rework before the next extension release. The
restored planning v1/v2 and sub-READMEs reverse PR #9's "one README / no per-member planning"
direction; CLAUDE.md updated to match so the convention and the tree agree.
**Outcome:** Root `ci.yml` parses (pyyaml safe_load OK; 8 jobs). Only a root-level
`.agents_workspace` remains. No live references to the old CHANGELOG/ARCHITECTURE paths outside
frozen history.

### Entry 25

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** Rework the per-project-plugin-toggler VSCode-extension release automation (the
root-level rework Entry 24 flagged as required), on branch `chore/pppt-release-workflow`.

**Context:** Entry 24 left the extension's `release.yml` inert: it lived in a subdir (GitHub only
runs `.github/workflows` at the repo root) and triggered `on: release [released]`, which in the
monorepo would fire on an unrelated repo-root release and try to attach the extension `.vsix` to
it. Two forks needed resolving: (a) how to trigger an extension release independently of repo
releases, and (b) how to sync the canonical CSS/icon into the webview on a Linux runner.

**Decision:**
- **Independent `pppt-v*` tag trigger.** Moved (`git mv`) to root
  `.github/workflows/release-extension.yml`, triggered by `push: tags: ['pppt-v*']` plus
  `workflow_dispatch`. This gives the extension its own version line decoupled from any repo-root
  release tag — resolving the tag-vs-package.json conflict that caused Entry 24 to omit the
  `version-tag` CI job. Folded that guard back in as an `Assert tag matches package.json` step
  (`${GITHUB_REF_NAME#pppt-v}` vs `vscode-extension/package.json`), gated on `event_name == push`
  so manual dispatch runs still package.
- **Single `ubuntu-latest` runner** (was a ubuntu+windows matrix). The `.vsix` is
  platform-independent JS/webview with no native modules — build once.
- **Explicit `cp` for CSS/icon sync, not the `prepackage` hook.** The extension's `prepackage`
  runs `make sync-css || powershell ... sync-css.ps1`; from the `vscode-extension/` dir there is no
  Makefile (it lives at the member root) so `make` fails, and the fallback calls `powershell`
  (Windows-only — absent on Linux; the runner has `pwsh`, not `powershell`). So on Ubuntu the hook
  path is fragile. Mirrored the proven `extension.yml` package-check job: explicit
  `cp html/styles.css …` (and `icon.svg`, to fully match the canonical `make sync-css`) from the
  member-root working-directory default, then `npx vsce package`.

**Impact / Risk:** Low. The workflow only fires on a `pppt-v*` tag, so it cannot disrupt repo-root
releases. It does not publish to the Marketplace (only attaches the `.vsix` to the GitHub release
for that tag) — adding `vsce publish` + a `VSCE_PAT` secret is the future upgrade path. Verified:
pyyaml `safe_load` OK; canonical `html/styles.css` and `html/icon.svg` exist; the nested
`apps/per-project-plugin-toggler/.github/workflows/` is now empty (untracked by git).
**Outcome:** Pending — needs a real `pppt-v0.9.1` tag push to verify end to end (current
`package.json` version is 0.9.1).

### Entry 26

**Type:** Decision
**Mode:** Interactive (user-directed, two AskUserQuestion forks resolved)
**Timestamp:** 2026-06-28T00:00:00Z
**Task:** Establish the repo's release model — per-component vs whole-repo tags, and per-component
changelogs — on branch `chore/pppt-release-workflow`.

**Context:** The user asked for tag-based releases that can target either a single component or the
whole repo, plus per-component changelogs, starting the plugin toggler at a tracked version. This
directly reverses the convention PR #10 (Entry 24) had just re-established: "members do not carry
their own CHANGELOG.md; release history lives in a single root changelog." Two forks went to the
user: (a) the toggler's version baseline given package.json is already 0.9.1, and (b) how much to
build now.

**Decision (user-chosen where noted):**
- **Two-axis tag model, non-overlapping namespaces.** Component release = `<alias>-vX.Y.Z`
  (`pppt-v*` for the toggler) triggering that component's workflow; whole-repo release = bare
  `vX.Y.Z`. `v*` never matches `<alias>-v*`, so they coexist. Documented in new `docs/releasing.md`
  (axis table + alias registry + per-component steps) and a new **Releases** convention bullet in
  root CLAUDE.md.
- **Per-component CHANGELOG.md restored** (reverses Entry 24). CLAUDE.md Docs convention amended:
  independently released components keep their own Keep-a-Changelog `CHANGELOG.md`; the repo keeps a
  root changelog once it cuts its first repo-wide release; un-released components carry none yet.
  Root + toggler READMEs repoint to the changelog/release guide.
- **Version baseline = keep 0.9.1** (user choice, over reset-to-0.0.1 or 1.0.0). The new
  `apps/per-project-plugin-toggler/CHANGELOG.md` starts at `[0.9.1] - 2026-06-12` as the first
  release *tracked in this monorepo*, with a note that 0.x development predates this repo and
  happened in a previous repository — so the prior per-version history is not reproduced here.
- **Scope = toggler component only** (user choice). The whole-repo `v*` axis is documented as the
  reserved namespace but its `release-repo.yml` + root CHANGELOG are deferred until the repo
  actually cuts a repo-wide release (YAGNI). `release-extension.yml` already triggers on `pppt-v*`
  and asserts tag == package.json (0.9.1), so no workflow change was needed.

**Impact / Risk:** Low. Reverses the just-merged "single root changelog" direction deliberately;
CLAUDE.md/READMEs updated so convention and tree agree. First component release is cut by tagging
`pppt-v0.9.1` on main once this branch merges.
**Outcome:** Pending merge of `chore/pppt-release-workflow`, then `pppt-v0.9.1` tag push to verify
the release workflow end to end.

### Entry 27

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-29T00:00:00Z
**Task:** Scrub stale old-project references from `apps/cross-repo-file-diff` and improve its diff
viewer without adding dependencies, on branch `feat/cross-repo-diff-viewer-upgrade`.

**Context:** The goal asked that the app be "up to date with no reference to the old project" plus an
"improved diff viewer without external library." The app was extracted from a standalone iterative-
planning repo whose planning artifacts (SKELETON/ITER docs, the TIDEWATER brand sheet) were already
removed, but leftover references to that lineage remained in code comments, CSS headers, CLAUDE.md,
and README: `v1/v2/v3` design-version labels, `ITER_04` cites, and the `TIDEWATER` codename. "Old
project" was read as that predecessor planning project/lineage — not the live product name "Vantage",
which is current branding and was kept.

**Decision:**
- Removed the version-lineage framing (`v1`/`v2`/`v3`, `ITER_04`, `TIDEWATER`) wherever it only
  pointed back at the old planning project, while preserving the real architectural constraints those
  sentences also stated (e.g. "sidebar has open|minimized modes, no close"). CSS header banners
  renamed to plain "Vantage — …".
- Diff-viewer improvement kept to three cohesive, dependency-free features: old/new line numbers in
  the gutter, word-level intra-line highlighting of changed spans within replaced lines (a second
  hand-rolled token-level LCS in `compare.js`, guarded at 400 tokens/line), and a `+N −M` change
  summary in the status row. Deliberately skipped stateful context-folding (minimal-change bias /
  YAGNI). Word highlight uses native CSS `color-mix()` (Chromium-only target already required).

**Impact / Risk:** Low. Pure additive render changes plus doc/comment edits; no new deps, no module
system change, `file://` constraint untouched. README/CLAUDE.md updated so docs match the new viewer.
**Outcome:** Pending manual check in Chromium (load order + diff render).

### Entry 28

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-29T00:00:00Z
**Task:** Add a runnable example for `apps/multi-repo-plan-runner`, clean its docs against the
user-operator-guide skill, and trim the README's overlap with the docs. Branch
`feat/multi-repo-plan-runner-example`.

**Context:** The goal asked for a "runnable example" with no chosen shape. docket resolves each
project `path` with `os.path.abspath` (CWD-relative), so a committed example registry cannot use a
machine-portable absolute path — it must use either relative paths (tied to the run directory) or
per-user absolute paths. Two forks the user left open: (1) how the example registry encodes paths,
and (2) whether the sample target repos are real git repos.

**Decision:**
- Example registry (`examples/docket.json`) uses **relative** project paths
  (`examples/sample-repos/...`) and the docs/README instruct running from the member root, where
  those resolve. Chosen over per-user absolute paths (not portable) and over adding a launcher/path-
  rewrite shim (new code for what one documented `cd` solves — write-less-code).
- Sample repos are plain directories with `.agents_workspace/planning/` plans, **not** real git
  repos — nested `.git` dirs inside the monorepo cause more trouble than they teach; the example
  demonstrates docket's UI/lifecycle, not git review. Noted as such in each sample README.
- Lifecycle sidecars written by the example are git-ignored
  (`examples/sample-repos/*/.agents_workspace/implementation/`) so the example always starts at
  `ready` on a clean checkout.
- Two projects (web-app with a nested `feature-search/ITER_01`, plus api-service) so the example
  also exercises plan nesting and per-project batch grouping.
- Docs cleanup: fixed two real inaccuracies (reference.md CLI table and install.md verify-line both
  omitted the `init`/`doctor` subcommands) and wired the example into the docs spine (index +
  getting-started). README trimmed from the full Install/Registry/Run duplication down to an
  overview + a pointer table into `docs/guide/`.

**Impact / Risk:** Low. No change to `docket/` source — only added `examples/`, doc edits, a
.gitignore rule, and a README rewrite. Verified live: `docket doctor` reports 0 errors/0 warnings,
`list_plans` returns all three plans as `ready`, and a manual `set_status` writes a git-ignored
sidecar.
**Outcome:** Example runs; docs and README consistent with the shipped CLI.

### Entry 29

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** Split usage-dashboard's dashboard.js and dashboard.css into smaller files.

**Context:** The dashboard serves plain (non-module) browser JS and CSS via a no-bundler
Python `http.server`. Splitting the sources into smaller files could be done either by
serving each part separately (multiple `<link>`/`<script>` tags + a generic static route)
or by concatenating ordered parts at serve time into the existing single responses.
**Decision:** Chose serve-time concatenation. `dashboard_server.py` now reads ordered
`_CSS_PARTS` / `_JS_PARTS` lists from `css/` and `js/` and joins them into the same
`/dashboard.css` and `/dashboard.js` responses. This needs zero HTML changes, adds no new
routes or path-traversal surface, and preserves the single global scope the inline
`onclick`/`onchange` handlers and shared top-level state (`lastData`, `sessionPage`) rely
on — so runtime output is byte-identical (verified: 0 code-line diffs for both bundles).
The JS bootstrap (`js/app.js`) must stay last in the list since order = concat order.
**Impact / Risk:** A future reader editing browser code must edit the split sources, not a
served file; the served bundle appears as one file in devtools. Mitigated by notes in the
member CLAUDE.md and README. No behavior change.
**Outcome:** py_compile + import + node --check + verbatim-diff checks all pass.

### Entry 30

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** Reorganize the usage-dashboard folder for navigability.

**Context:** The member root mixed 6 Python modules, the frontend (html/css/js), 2
PowerShell scripts, and config files flat. User chose "full grouping" over "light
grouping" when asked.
**Decision:** Moved (via `git mv`, history preserved) the 5 non-entry Python modules
into `backend/`, the UI into `web/` (dashboard.html + css/ + js/), and the two `.ps1`
into `scripts/`. `usage-dashboard.py` (entry) and config stay at root. Path fixes:
entry puts `backend/` on `sys.path` (keeps the backend's flat cross-imports working);
`dashboard_server.py` asset dir → `../web`; `usage-dashboard-start-once.ps1` computes
the app root as `Split-Path $PSScriptRoot -Parent` for its uv `--project`/entry paths.
Also fixed `setup/registry.ps1`: its `SetupScript` path now points into `scripts/`, and
its `Detect` probe now looks for the task name `usage-dashboard` (not the stale
`StartStatuslineServer`) — the latter was a latent bug from the earlier task rename in
this branch, surfaced while editing the same descriptor.
**Impact / Risk:** Cross-member touch of `setup/registry.ps1` was required because the
reorg moved the setup script it delegates to; still pure delegation (no install logic
moved), so the no-cross-member-dependency invariant holds. Docs (member README +
CLAUDE.md) updated for the new paths.
**Outcome:** App runs from the new layout — smoke test on :8098 returns 200 for /,
/dashboard.css, /dashboard.js, /api/data with identical asset sizes.

### Entry 31

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** Nest all scheduled tasks under `\ClaudeAutomation\`, and expose the statusline-hook
config-dir override in the setup registry.

**Context:** Two issues. (1) The CLAUDE.md convention puts every Task Scheduler task under the
shared `\ClaudeAutomation` root, but `file-sync` registered at `\file-sync\` and the three session
digests at `\ScheduledSessionDigests\` — both outside the root. (2) `statusline-hook-setup.ps1`
accepts `-ClaudeDir`, but the `setup/registry.ps1` descriptor never forwarded it, so an orchestrator
install could not target a non-default config dir the way a direct script call can.
**Decision:**
- Task folders: `file-sync` → `\ClaudeAutomation\file-sync\` (added the missing leading `\` on the
  user's in-progress edit); the three digests → `\ClaudeAutomation\<member>\`, where `<member>` is
  derived at runtime from the member folder name (`Split-Path -Leaf (Split-Path -Parent
  $PSScriptRoot)`, since each digest's `install.ps1` sits one level below the member root) rather
  than a hardcoded `ScheduledSessionDigests` — mirroring file-sync's `Split-Path -Leaf $PSScriptRoot`
  so the subfolder is self-identifying and survives a member rename. Resolves to
  `\ClaudeAutomation\scheduled-session-digests\`. Kept the per-tool subfolder rather than flattening
  tasks directly under the root, matching the CLAUDE.md "subfolders such as the case for file sync"
  allowance. Updated the `file-sync` Detect probe in
  `registry.ps1` to the new path and the file-sync CLAUDE.md invariant text. Digest uninstall/detect
  match by task name (path-agnostic), so they needed no change; `git-sync` registers no task.
- statusline: registry `Install` now forwards `-ClaudeDir` from `$Config.claudeDir` and records it;
  `Uninstall` and `Detect` replay the recorded `claudeDir`. Documented the key in the config example.
**Impact / Risk:** Behavior change — tasks previously installed at the old paths are orphaned; users
should uninstall via the prior script revision (or delete the old Task Scheduler folders) before
reinstalling. Cross-member touch of `setup/registry.ps1` stays pure delegation, so the
no-cross-member-dependency invariant holds.
**Outcome:** All five edited PowerShell scripts parse clean (AST parse-check); not run against a live
Task Scheduler.

### Entry 32

**Type:** Decision
**Mode:** Interactive (user-directed)
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** statusline-hook multi-dir install support, and redefine `install -All` scope to the
config's opt-in list.

**Context:** Two follow-ups from using the orchestrator. (1) statusline-hook could only wire into
one config dir per install — the descriptor took a scalar `claudeDir` and the manifest keys one
entry per member, so a second install overwrote the first. (2) `install -All` installed every
registered member whose *required* config was satisfied, so members with no required config
(`scheduled-session-digests`) installed with defaults even when absent from `config.json`, which the
user found surprising.
**Decision:**
- statusline-hook: reworked the `registry.ps1` descriptor to the file-sync `instances` pattern —
  `Install` normalizes config to a list (an `instances:[...]` array, or a single `{variant,
  claudeDir}` object for back-compat), installs each dir, and records `{instances:[...]}` for
  replay; `Uninstall` loops the recorded instances (legacy single-form entries still handled);
  `Detect` probes every recorded dir's `settings.json` and reports installed if any has `statusLine`.
- `install -All` scope: now installs only members with an entry in `config.json` (even an empty
  `{}`); a member absent from config is skipped with a note. Chose key-presence as the opt-in signal
  (user picked "only members listed in config" over keeping the old behavior). Guarded by `$All`, so
  `install -Member <name>` still installs a single member with defaults and no config entry. This
  reverses the prior `setup/CLAUDE.md` invariant, which was updated along with the README.
**Impact / Risk:** Behavior change to `-All` — anyone relying on it to install config-less members
without listing them must now add a `{}` entry or use `install -Member`. Confined to `setup/`; still
pure delegation, so the no-cross-member-dependency invariant holds.
**Outcome:** `command-center.ps1` and `registry.ps1` parse clean; dry-runs confirm the statusline
array resolves to 2 instances (legacy object → 1) and `-All` against the user's config installs the
4 listed members and skips the unlisted `scheduled-session-digests`. Not run against a live install.

### Entry 33

**Type:** Decision
**Mode:** Interactive (user-directed)
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** Drop `C4_CLAUDE_DIR` from statusline-hook; make the config dir an install arg (default
`~/.claude`) and have each hook variant self-locate its config dir.

**Context:** statusline-hook resolved its base config dir from `$C4_CLAUDE_DIR` in all three variants,
the setup script, and the registry `Detect` probe. The user wanted the dir supplied explicitly at
install time (defaulting to `~/.claude`) and the hooks to derive it from where they are installed —
since the setup script copies each hook into the chosen config dir, the script's own folder *is* that
dir. This also makes the multi-instance install (Entry 32) self-consistent: each installed copy
exports under its own dir with no shared env var.
**Decision:**
- Variants self-locate: ps1 `$PSScriptRoot`, sh `cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd`,
  py `Path(__file__).resolve().parent`. Removed all `C4_CLAUDE_DIR` reads from the three hooks.
- Setup script: `-ClaudeDir` now defaults to `~/.claude` via a param default; removed the
  `$C4_CLAUDE_DIR` fallback block entirely.
- **Wired command now points at the actual installed script** (`$destScript`) instead of a hardcoded
  `~/.claude/statusline-hook.<v>`. This was a latent bug — a custom `-ClaudeDir` install copied the
  hook to the new dir but wired settings.json to run the home copy. Trade-off: the stored command is
  now an absolute, quoted path rather than the portable `~/…` form; correctness across dirs (and the
  multi-instance feature) outweighs settings.json portability for a personal tool.
- Registry `Detect` default dropped its `C4_CLAUDE_DIR` fallback → plain `~/.claude`.
- Left `C4_CLAUDE_DIR` untouched for its other consumers (`usage-report`, `usage-dashboard`,
  `claude-usage`, `claude-plugins`, `claude-component-browser`, `setup/`); updated only statusline
  docs and removed statusline from the root README's consumer list.
**Impact / Risk:** Behavior change — a prior custom install driven purely by `$C4_CLAUDE_DIR` (no
`-ClaudeDir`) now lands in `~/.claude`; users must pass `-ClaudeDir`/`claudeDir`. Existing default
installs are unaffected except the settings.json command string changes to an absolute path on
reinstall. The export path contract with `usage-dashboard` still holds for the default dir.
**Outcome:** All statusline PS scripts parse clean; `statusline-hook.py` compiles; `statusline-hook.sh`
passes `bash -n`; no `C4_CLAUDE_DIR` reads remain in the tool. Not run against a live Claude session.

### Entry 34

**Type:** Decision
**Mode:** Interactive (user-directed)
**Timestamp:** 2026-07-01T00:00:00Z
**Task:** Move the Claude dir and project dir selection in `claude-component-browser` out of
startup (env/CLI) and into the UI; the server takes only `--host`/`--port`.

**Context:** The browser resolved its Claude dir from `$C4_CLAUDE_DIR` (first pathsep entry, via
`claude-plugins`) and its project root from `--project-dir`/cwd, all fixed at launch. The
first-entry-only behavior was opaque to the user. User chose (via prompt): a single Claude dir and
single project dir, entered in the UI, and to drop `$C4_CLAUDE_DIR` from the browser entirely
(prefill `~/.claude` + cwd instead). Two design forks were mine to resolve.

**Decision:**
- **Library threading (fork 1):** added an optional `claude_dir: Path | None = None` to
  `plugins_base`, `loose_bases`, and `load_installed_plugins` in `claude-plugins`, defaulting to
  the existing env resolution (extracted to a private `_default_claude_dir`). Backward-compatible:
  `per-project-plugin-toggler` (only other consumer, calls `load_installed_plugins(project_root)`)
  is untouched and still honors `$C4_CLAUDE_DIR`. Rejected removing the env default from the library
  — that would break the toggler and exceed the browser's scope. The browser now always passes an
  explicit dir and never reads the env var.
- **Server state (fork 2):** `/api/members` takes `claude_dir` + `project_dir` query params, scans
  on demand, and stores the result in the class-level `Handler.members` cache; `/api/member?id=N`
  still indexes that cache (path never crosses the wire — traversal guard preserved). Single shared
  cache, no per-request keying: this is a localhost single-user tool, so last-scan-wins is fine and
  a mid-rescan id fetch degrading to 404 is acceptable. Added `/api/config` returning `~/.claude` +
  cwd for UI prefill. Blank/missing/nonexistent dirs fall back to defaults and scan to empty
  (library already degrades gracefully) — no hard validation.
- **UI:** two text inputs + Scan button, values persisted per browser in `localStorage`.

**Impact / Risk:** `claude-plugins` public API gains optional params (semver minor; not bumped —
no release requested). Browser behavior change: `$C4_CLAUDE_DIR` no longer affects it; users pick
the dir in the UI. Everything is still bound to `127.0.0.1`.
**Outcome:** `claude-plugins` and `server.py` pass py_compile + ruff + mypy strict. Smoke-tested
live: `/api/config` returns native Windows paths; scanning with an explicit Claude dir populates
the cache; `/api/member?id=0` loads the body from it; nonexistent dirs return an empty list.

### Entry 35

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-02
**Task:** multi-repo-plan-runner — block Implement (headless + batch) on already-implemented plans in both frontends.

**Context:** `run_implement`, `RunManager.submit`, and both UIs treated `implemented` as
re-runnable (`status in ("ready","implemented")`). The user wants an implemented plan to be
non-implementable and non-batch-selectable until explicitly reopened. The lifecycle table
(`tracker.ALLOWED`) still declared `("implemented","running"): {"headless"}` legal — a
contradiction with the desired behavior and a latent bypass.
**Decision:** Enforce `ready`-only at the core entry points (`run_implement`, `submit`), gate the
UIs to match (webui: Implement button disabled + batch checkbox disabled unless `ready`; TUI:
`action_implement` and `action_toggle_select` refuse non-`ready` with a log message), AND removed
the now-unreachable `("implemented","running")` edge from `tracker.ALLOWED` so the state machine
itself forbids re-implementing. Re-implementing remains possible via the existing manual
`implemented -> ready` reopen, then `ready -> running`. Did not edit the archived architecture doc
(frozen history); this entry records the state-machine change.
**Impact / Risk:** Behavior change — implemented plans must be reopened before re-running.
`run_myself` (manual, does not go through `run_implement`) intentionally left available for
implemented plans; only running blocks it, unchanged. No new dependencies.
**Outcome:** `uv run pytest` green (196 passed) at 100% line+branch coverage; py_compile clean.

### Entry 36

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-03
**Task:** usage-dashboard — feature scope for the "/goal: most sought-after Claude Code metrics dashboard" session.

**Context:** The goal was open-ended ("becomes the most sought after dashboard ... keep the
current theme") with no feature list. Needed to choose which capabilities to add and where to
compute them.
**Decision:** Scoped the release to the headline features popular alternatives (ccusage,
Claude-Code-Usage-Monitor) are known for, computed server-side per the member invariant:
(1) cache savings in USD + cost-without-cache (pricing math from per_model tokens, always the
estimate, independent of the live actual-cost overlay); (2) month-to-date cost + linear month-end
projection; (3) 12-month GitHub-style activity heatmap (`stats.heatmap`, 364 days; client maps
tokens to 5 quartile intensity levels — presentational scaling only, kept client-side like
existing bar-width math); (4) sortable Recent Sessions columns (display-order only, client-side);
(5) `/api/export.csv` sessions export. Replaced the "Output Tokens" stat card (still visible in
the Token Breakdown card) with "This Month" and upgraded "Cache Savings" from tokens to USD.
Heatmap widened from an initial 26 weeks to 52 so the full-width card is visually filled.
**Impact / Risk:** Payload contract grew (new stats keys + `heatmap`); server and js changed
together per the invariant. Pre-existing mypy `var-annotated` errors in session_stats/
live_statusline (un-annotated defaultdicts) left untouched — not introduced by this change.
**Outcome:** Verified end-to-end in Chrome (both themes): heatmap renders, sort works, CSV
downloads with attachment headers. Fixed one collision found in verification: heatmap pad cells
named `.empty` inherited the dashboard empty-state padding; renamed to `.pad`.

### Entry 37

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-03T20:15:00+02:00
**Task:** Plan usage-dashboard v4 (insight layer) — cost policy

**Context:** User excluded the pricing-staleness feature stating "the live pricing is not reliable. The one calculated from pricing table is more reliable." The existing invariant ("actual cost wins for live sessions", merge.py overlay) directly contradicts that judgment, and v4's new aggregates (deltas, range totals, plan value) need one canonical cost.
**Decision:** v4 makes the pricing-table estimate canonical everywhere; ITER_02_v4 removes merge._apply_actual_cost and rewrites the CLAUDE.md/README invariant. Actual cost stays visible only informationally in the live card's per-session table.
**Impact / Risk:** Totals for currently-live sessions shift slightly (estimate vs statusline figure). Reverses a documented invariant — flagged to the user in the planning summary for veto before implementation.
**Outcome:** Planned in ITER_02_v4; not yet implemented.

### Entry 38

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-03T20:15:00+02:00
**Task:** Plan usage-dashboard v4 — live-card freshness transport

**Context:** The approved feature list said "SSE push for the live card". SSE on the stdlib threading server adds connection-lifecycle code for a single local client; the underlying goal is ~10s freshness for rate limits.
**Decision:** Deliver the goal via a cheap GET /api/live endpoint (statusline files only, no transcript parse) polled every 10s; full payload stays at 60s. True SSE recorded as out-of-MVP upgrade path (payload shape is transport-agnostic).
**Impact / Risk:** Slightly higher request churn than SSE; negligible locally. If the user insists on SSE, ITER_05_v4 §04 is the only artifact to revise.
**Outcome:** Planned in ITER_05_v4; user confirmed fast-poll on 2026-07-03.

### Entry 39

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-03T20:15:00+02:00
**Task:** Plan usage-dashboard v4 — plan family location and naming

**Context:** User said "put the plans under v4". Existing planning/ uses version subfolders (v1..v3) with untagged filenames; the plan-build-review skill's canonical form is a _vN filename suffix, which the implement-from-plan step keys on.
**Decision:** Both: .agents_workspace/planning/v4/ folder (repo convention) with _v4-suffixed stems inside (SKELETON_v4.md, ITER_01_v4..ITER_05_v4.md) so depends_on stems and the implementation skill's version detection work unambiguously.
**Impact / Risk:** None; prior v1–v3 artifacts untouched.
**Outcome:** Six artifacts written.

### Entry 40

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-04T00:35:00+02:00
**Task:** Implement usage-dashboard v4 (SKELETON_v4 → ITER_05_v4) — stat-card trend deltas

**Context:** ITER_03_v4 § 05 says the Total Tokens, Est. Cost, *and* Cache Savings cards each get a delta line "from `stats.delta`". But the payload contract (SKELETON_v4 § 02) defines `delta` with only `{tokens_pct, cost_pct, sessions_pct}` — there is no savings delta, and computing one client-side would need the previous window's savings (not sent) and would violate the "all computation server-side" invariant.
**Decision:** Render the delta line only where the payload carries a matching metric: Total Tokens ← `tokens_pct`, Est. API Cost ← `cost_pct`. Cache Savings shows no delta line. `sessions_pct` stays in the contract for future use.
**Impact / Risk:** One of the three named cards lacks its delta line; faithful to the payload contract and avoids fabricating a figure in the browser. Upgrade path: add `savings_pct` to `summarize_sessions._delta` and the payload if a savings trend is later wanted.
**Outcome:** Deltas render correctly (verified in-browser: ▲/▼ green/red with "vs prev <N>").

### Entry 41

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-04T09:00:00Z
**Task:** usage-dashboard visual glitch pass (5 reported issues).

**Context:** Issue 4 asked that "every card title whose content changes with the range
filter" show a "(Last X)" window suffix. Ambiguous which surfaces count: stat cards use a
`.label` not a `.section-title`, and several cards (This Month, Plan Value, Activity profile,
Top Tools) are deliberately NOT range-scoped. Issues 3 and 5 turned out not to be code bugs.

**Decision:**
- Added a `rangeSuffix` ("(last 7 days)"…"(all time)") to exactly the range-scoped surfaces:
  the three range-scoped stat labels (Total Tokens, Est. API Cost, Cache Savings), Token
  Breakdown, Cost by Model, Expensive Sessions, Top Projects by Tokens, Usage by Model,
  Recent Sessions. Left the non-range cards (This Month, Plan Value, Activity profile, Top
  Tools, rate limits) plain, and left the daily charts / heatmap on their existing accurate
  "(last N days / 12 months)" — those reflect the 90-day chart cap, not the range.
- Issue 2: model drill-down filtered by *family* (`modelFamily`), so Sonnet-5 pulled in
  Sonnet-4-6. Switched to `modelMatches()` — exact-id match for specific models (which carry a
  version digit) and family match only for the bare family keys the model-mix legend emits
  (`claude-sonnet`, no digit). Digit test chosen over a hardcoded family list to avoid
  duplicating claude-usage's MODEL_COSTS keys in JS.
- Issue 1: the two standalone `.card`s (model-mix, activity-profile) were direct #main children
  with no bottom margin. The two cards that DID space (`.rl-card`, `.hm-card`) each did so via a
  single-purpose class whose only declaration was `margin-bottom: 12px`. Rather than add a third
  one-off, generalized to `#main > .card { margin-bottom: 12px }` and deleted the two redundant
  rules — one mechanism, less CSS. `.rl-card` class stays (it's a JS hook in app.js); `.hm-card`
  was dropped from markup since it had no other use. Grid-nested cards are unaffected (not direct
  children).

**Impact / Risk:** Low. JS/CSS only; server payload contract unchanged. Family-legend filtering
verified still 107 sonnet sessions; specific Sonnet-5 now 1 (was 107).

**Outcome:** All three code fixes verified in-browser. Issues 3 (April/May empty) and 5
(only ≤90d) are not bugs — see summary.

### Entry 42

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-04T10:00:00Z
**Task:** usage-dashboard — make Top Tools and the daily bar charts honour the range filter.

**Context:** Two follow-ups. (1) Top Tools ignored the range filter because `Activity.tools`
is a single all-time global counter with no per-day attribution. (2) `by_day` / `model_mix`
were hard-capped at 90 bars (`CHART_DAYS`), so 12m/all looked identical to 90d.

**Decision:**
- Added per-day tool buckets (`Activity.daily_tools`, keyed day -> tool -> count) to the shared
  `claude-usage` library, keeping the existing all-time `Activity.tools` for back-compat (only the
  dashboard + one library test read `.tools`; `usage-report` does not). The dashboard now windows
  `daily_tools` over the same day-slice as the daily series, so Top Tools tracks the range.
  Scoped to RANGE only, not project — the Activity series stay project-agnostic per the existing
  invariant, and tool blocks carry no project attribution in the accumulator.
- Lifted the 90-day cap: the daily window now follows the range (N days for 7d/30d/90d, the full
  retained ~year for 12m/all). Kept the accurate "(last N days)" day-count titles on the daily
  charts rather than switching to "(all time)", since those charts only ever plot the retained
  364 days — a day count is honest, "all time" would over-claim.
- Added a dynamic x-axis label step (~14 labels max) in both bar charts so a year of daily bars
  stays readable instead of smearing labels.

**Impact / Risk:** Low-moderate. `claude-usage` gains one additive public field (minor semver);
100% coverage held with an extended tool test (incl. the no-timestamp fallback). Dashboard payload
shape unchanged. Removed the now-unused `CHART_DAYS`; left the pre-existing unused `HEATMAP_DAYS`
constant and the pre-existing mypy `buckets` var-annotation gaps alone (not mine to fix here).

**Outcome:** Verified: by_day/model_mix scale 7->7 … 12m/all->364; Top Tools Bash count grows
696 (7d) -> 2107 (90d+); charts render with clean labels in-browser.

### Entry 43

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-04T11:00:00Z
**Task:** usage-dashboard — weekly rollup for long-range daily charts + cleanups.

**Context:** After uncapping the daily charts (Entry 42), 12m/all rendered ~364 daily bars
(2px, mostly empty for short-history users). The user asked to roll long ranges up to weekly.

**Decision:**
- Roll the daily series (by_day + model_mix) into 7-day, oldest-aligned buckets when the window
  exceeds `DAILY_BAR_LIMIT` (90 days); 7d/30d/90d stay daily. Server exposes the granularity as a
  new `stats.chart_bucket` ("day"|"week") key rather than having the browser re-derive the
  threshold — keeps the computation server-side per the payload-contract invariant, rendered in
  the same change.
- Titles switch to a "Daily"/"Weekly" prefix + the shared range suffix ("Weekly Token Usage
  (last 12 months)"), replacing the old bar-count "(last N days)" which read "(last 364 days)".
- Disabled the per-bar day drill-down on weekly bars: a weekly bar's date is only its first day,
  so filtering sessions to it would show a misleading 1/7 slice. Daily bars keep the drill-down.
- Cleanups the user asked for: removed the unused `HEATMAP_DAYS` constant, annotated the two
  `_by_project`/`_by_model` `buckets` defaultdicts (mypy `var-annotated` gaps now clean), and
  switched `tests/smoke.sh` from bare `python3` to `uv run python` so the workspace `claude_usage`
  dep resolves.

**Impact / Risk:** Low. Additive `chart_bucket` key (render + server changed together); by_day /
model_mix shapes unchanged. session_stats.py now fully ruff+mypy clean. Smoke test passes.

**Outcome:** Verified in-browser — 30d daily (30 bars), 12m/all weekly (52 bars); smoke `PASS`.

### Entry 44

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-10T00:00:00Z
**Task:** Plan the v5 family (planning/v5/) — roundtable, the turn-based multi-repo workspace succeeding multi-repo-plan-runner.

**Context:** User chose the stack (stdlib Python + vanilla JS) and member framing (new app) via AskUserQuestion; the remaining forks inside the plan were left to me. "Try not to defer anything" set the MVP-boundary bias.
**Decision:**
- Member/naming: `apps/multi-repo-workspace/`, internal name `roundtable` (descriptive folder per repo convention; short internal name mirroring docket's pattern).
- Reuse strategy: fork-and-adapt docket's registry/tracker/plans/runner machinery rather than extracting a `libs/` member — the copies diverge at birth (new registry keys, sessions, persisted run output), and extraction would force an out-of-scope docket refactor. The one kept-in-sync contract is the implementation-sidecar JSON format, registered in `docs/shared-plugin-logic.md` with Cross-reference comments in both trackers (single sanctioned docket edit, planned in ITER_01_v5). Lib extraction revisited only on a third consumer.
- Freshness model: board/round pages poll (5s/3s); SSE only for live token streams (session turns, order runs) — usage-dashboard v4 fast-poll precedent.
- Concurrency: one per-project lock shared by planning turns and implement runs; planning turns acquire non-blocking (409 repo_busy to the user), the executor blocks (orders queue). Prevents plan/implement interleaving in one repo.
- MVP boundary under "defer nothing": git **commit** is inside the MVP (safe, locally reversible, closes the review loop); push/branch/PR automation stays out. Browser-only (no TUI), zero runtime deps.
- Round model: exactly one non-done round; closing a round auto-opens the next and carries forward follow-up notes (unaddressed carried items roll again).
**Impact / Risk:** Plan-level only (no code yet). Fork-not-lib accepts deliberate duplication of ~4 small modules; the sidecar-format contract keeps docket and roundtable interoperable on the same repos. Trigger vocabularies differ (`headless` vs `round`) — treated as opaque display strings by both.
**Outcome:** Family delivered: planning/v5/SKELETON_v5.md + ITER_01..04_v5.md; ITER_04_v5 is the mvp:true terminator.

### Entry 45

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-07-10T00:00:00Z
**Task:** v5 family scope expansion — user pulled per-run cost metrics, in-app file editing, and full markdown rendering into the MVP.

**Context:** The three items were on ITER_04_v5's deferred list; the user asked for them in-MVP, suggesting claude-usage reuse for costs. Forks: where to land them (edit the hours-old unbuilt family in place vs append an ITER_05 grab-bag), how to source cost (parse transcripts vs the stream-json result event), and how to get "full markdown" without a framework.
**Decision:**
- Edited the family in place: each item lands in its natural iteration (editing + markdown in ITER_01, cost capture in ITER_02 via a new costs.py, order/round costs in ITER_03, cost surfacing in ITER_04). No artifact is built yet, so the delivered-artifact immutability rule does not bind; an ITER_05 of three unrelated leftovers would have been worse decomposition.
- Cost source: the result event's token counts fed to claude_usage.estimated_cost (roundtable = the lib's third consumer, uv path dep; no transcript parsing). Estimate-canonical, reported total_cost_usd informational — inherits the usage-dashboard v4 cost policy. Unknown model => null, rendered n/a, never 0.
- File editing: PUT file route guarded by the existing traversal check + 1 MB cap + binary reject + repo-lock 409 + expect_mtime optimistic-concurrency 409 (no server-side merge). UI is a plain textarea (structured editor deferred). Required rewording the SKELETON "plans app-read-only" paragraph into a repo-write policy: no autonomous writes; explicit user actions (file save, commit) and Claude sessions are the only repo writers.
- Full markdown: vendored pinned single-file marked.min.js + dompurify.min.js under static/vendor/ (no npm, no build step) replacing the planned minimal md.js — hand-rolling CommonMark would be more code than the wrapper, violating write-less-code.
**Impact / Risk:** "Zero runtime deps" claim softened to "one in-repo stdlib-only dep + two vendored JS assets". File editing widens the app's write surface; mitigations above keep it explicit-user-action-only. Deferred list updated (analytics layer, structured editor, tree-level file management remain out).
**Outcome:** All five v5 artifacts updated in place; cross-iteration audit re-run mentally (no forward refs introduced; costs.py declared in SKELETON tree [02], consumed 02/03/04; vendor assets declared in SKELETON §03, landing in 01).
