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