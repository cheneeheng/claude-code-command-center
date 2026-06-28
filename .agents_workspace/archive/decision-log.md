# Archived Decision Logs

Consolidated historical agent decision logs from across the monorepo. These were
previously scattered in per-member `docs/claude_logs/DECISION_LOG.md`,
`.agents_workspace/DECISION_LOG.md`, and `docs/automation-suite-decision-log.md` files.
They are frozen here as a record; the active going-forward log is
`.agents_workspace/DECISION_LOG.md` at the repo root.

Entry content is preserved verbatim. The only structural change is that
`cross-repo-file-diff`'s top-level `## N` entry headings were demoted to `### N` so they
nest under their member section.

---

## apps/cross-repo-file-diff

_Source: `apps/cross-repo-file-diff/docs/claude_logs/DECISION_LOG.md`_

### 1

- Type: Decision
- Mode: Autonomous
- Timestamp: 2026-06-13T21:15:57Z
- Task: Implement Vantage MVP from SKELETON+ITER_01..05.
- Context: Six plan docs (SKELETON + 5 iterations) each rewrite §02/§05 additively for a 3-file static app.
- Decision: Built directly to the cumulative final MVP state (union of all iteration features) in one pass rather than six sequential file rewrites, since iterations are additive deltas over the same three files. Equivalent end state to running the full sequence to the mvp:true terminator.
- Impact/Risk: A missed iteration detail would not be caught by an intermediate step; mitigated by checking each feature against its source iteration spec.
- Outcome: All 10 MVP checklist features implemented across `index.html`, `vantage.css`, `vantage.js`. `node --check vantage.js` passed with no errors. HTML correctly references both `vantage.css` and `vantage.js` via classic `<script src="vantage.js">` (no `type="module"`), satisfying the `file://` constraint from §03.

### 2

- Type: Decision
- Mode: Autonomous
- Timestamp: 2026-06-14T00:00:00Z
- Task: Implement the v2 plan family (SKELETON_v2 → ITER_01_v2 → ITER_02_v2, mvp:true terminator) on branch `feat/v2-single-file-redesign`.
- Context: Three v2 plan docs additively rewrite §02/§05 for a single-file reshape of v1; ITER_01_v2 and ITER_02_v2 both touch the same `index.html`. Several spec points left implementation choices open.
- Decision: (a) Built directly to the cumulative final MVP state in one pass rather than three sequential rewrites of the same single file — same approach as Entry 1; equivalent end state to running the sequence to the terminator. (b) Dropped the Tidewater brand sheet's `@import` of Google Fonts when inlining it: it is a network call, which violates the hard "no network calls" constraint and the offline-capable goal; the brand type tokens already declare Georgia/system-ui/monospace fallbacks (skeleton §03 explicitly sanctions falling back to system fonts). (c) Collapsed v1's three files into one `index.html` per §03 ("exactly one file") — `git rm vantage.css vantage.js`. (d) Removed v1's sort dropdown: v2 §05 specifies the board is "sorted by last activity" and the header component tree lists only BoardFilter, so the sort control is out of scope; board now always sorts by last activity. (e) Removed v1's persistent footer selection bar (not in the v2 component tree); added a "Clear" control to the sidebar header and the Copy A→B / B→A buttons to the sidebar footer — the §01 concept core flow requires copy-across, and since selection persists across close/minimize a clear affordance is needed to reset A/B. (f) VSCode URI composition normalizes backslashes→forward-slashes, trims trailing slashes, and forces a leading "/" so Windows drive paths render `vscode://file/C:/...` and POSIX paths `vscode://file/Users/...` (per ITER_02_v2 build-time note on slash format).
- Impact/Risk: A missed iteration detail would not be caught by an intermediate build step; mitigated by checking each feature against its source iteration spec. Adding Clear/Copy controls and removing sort are minor deviations from the literal component tree but keep the core flow usable; flagged here rather than silently. VSCode URI format verified by composition logic but not exercised against a live VSCode install.
- Outcome: Single `index.html` (brand tokens + component CSS + classic inlined script). Extracted script passes `node --check`; all 31 `getElementById` references resolve against declared element ids. Board (filter, last-activity sort), expandable cards + lazy file tree, A/B selection, slide-in diff sidebar (close/minimize→puck, selection-preserving, cached diff), Open-in-VSCode button (disabled until root path set), and root-path IndexedDB persistence all implemented. Jump-to-repo / Ctrl+K search removed.

### 3

- Type: Decision
- Mode: Autonomous
- Timestamp: 2026-06-15T00:00:00Z
- Task: Implement the v3 plan family (SKELETON_v3 → ITER_01..04_v3, mvp:true terminator) on branch `feat/v3-multi-file-redesign`.
- Context: Five v3 plan docs additively rewrite §02/§05 to reshape v2's single inlined `index.html` into multiple classic-script files, plus two surface changes (sidebar can only be open|minimized — no close; board cards highlight comparison state). All four iterations touch the same module files.
- Decision: (a) Built directly to the cumulative MVP state in one pass (same approach as Entries 1–2) rather than re-stubbing then filling the same files four times — equivalent end state to running the sequence to the terminator, each feature checked against its source iteration. (b) Split into `styles/{tokens,layout,components}.css` and `scripts/{namespace,persist,scanner,compare,copy,editor,ui,app}.js` per the §02 layout; `window.Vantage` namespace + load order replace import/export. The v2 `App` namespace became `Vantage.UI`. (c) Sidebar lost its close (×) and its in-header Clear; per ITER_02 §05 the clear/swap moved to a new persistent **selection bar** (sticky under the toolbar, shown once any side is set) which is the bridge to the sidebar. Clearing the selection is now the only way to remove the comparison surface (no dismiss path while both sides are set), satisfying the v3 invariant. (d) `Editor.vscodeUri(repoName)` adopted the plan's one-arg signature by holding `Editor.rootPath` internally, synced via `Editor.setRootPath()` from UI on load/save/clear — keeps the call synchronous for render. (e) `Selection` entry field renamed v2 `fileHandle` → `handle` to match the SKELETON_v3 §02 data model. (f) Re-added a sort control (last-activity default / A–Z / stack) per ITER_01 §05, which v2 had removed. (g) Board highlights: `.is-compare-a/-b` (derived from Selection, with A/B badges) and `.is-active` (the expanded/drilled-into card) computed each render, nothing persisted.
- Impact/Risk: A missed iteration detail would not be caught by an intermediate build; mitigated by per-feature spec checks. CLAUDE.md and README still describe the v2 single-file architecture and its now-superseded "single file / do not split" constraint — left unchanged (out of plan scope) and flagged to the user as a follow-up, since this branch deliberately reverses that constraint. VSCode URI format verified by composition logic, not against a live VSCode install. No browser runtime test performed; validation limited to `node --check` and id cross-referencing.
- Outcome: Multi-file static app: `index.html` (markup + ordered `<link>`/`<script>`), 3 CSS files, 8 JS modules. All 8 scripts pass `node --check`; every `getElementById` id in `ui.js` resolves against `index.html`; no dangling references to the removed close/clear controls. Implements live board (filter/sort/rescan/reconnect), lazy file trees, A/B selection with selection bar + board highlights, line-based diff sidebar (open|minimized→puck, selection-preserving, cached lastDiff), copy/overwrite behind confirm, and Open-in-VSCode gated on the optional root path.

### 4

- Type: Decision
- Mode: Autonomous
- Timestamp: 2026-06-15T00:00:00Z
- Task: Post-v3 card-interaction refinements on branch `feat/v3-multi-file-redesign` (selection/hover/chevron/swap tweaks requested interactively).
- Context: User feedback on the live v3 board: the `.is-active` highlight fired only on expand; A's outline was indistinguishable from the selected outline (both teal); swap auto-reopened a minimized sidebar; chevron was hard to hit; hover highlighted only the title. SKELETON_v3 §05 explicitly reserved `.is-active` for "an explicit repo-pick action rather than expanded," so this is in-plan, not a deviation.
- Decision: (a) Decoupled select from expand (user-chosen via AskUserQuestion): clicking anywhere on a card sets visual focus (`.is-active`); only the chevron expands. "Select" is visual-only — it never touches the A/B comparison. (b) Selected state changed from a neutral ink ring to a fill+lift (`--surface-2` bg, `--fg-muted` border, `shadow-md`) per user preference; chose a neutral treatment because both brand accent hues are taken (teal=A, terracotta=B) and their compare borders still paint on top. (c) Deselect implemented via a single document-level click listener using `e.target.closest('.repo-card')` (clicks outside any card clear focus) plus second-click-toggles-off in `selectCard` — avoids per-element handlers. (d) Chevron force-selects (sets active, not toggle) so clicking it always leaves the card selected. (e) Swap no longer routes through `onSelectionChanged`: it preserves the current sidebar mode (a minimized panel stays minimized) and only recomputes the diff when the panel is open; a minimized panel recomputes lazily on reopen (`lastDiff` nulled). (f) Added a swap control to the sidebar header mirroring the selection bar. (g) Whole-card hover highlight (moved `:hover` from `.repo-card-header` to `.repo-card:not(.is-active)`, background-only so it doesn't stomp compare borders); chevron is now the only element with button/pointer affordance and a real padded hit area.
- Impact/Risk: Selected fill and non-selected hover both use `--surface-2`; selection leans on border + elevation to distinguish — flagged to user as possibly subtle, with a bump path offered. Document-level click listener fires on all out-of-card clicks (toolbar/sidebar/modal) and clears board focus — harmless since focus is purely visual. No browser runtime test; validation limited to `node --check` on `ui.js`.
- Outcome: `scripts/ui.js`, `styles/components.css`, `index.html` updated. `ui.js` passes `node --check`. Card interaction model: click=select (toggle), empty-space/second-click=deselect, chevron=expand+force-select, file rows=assign A/B (stop propagation), swap=reorder without reopening the sidebar.

---

## apps/multi-repo-plan-runner

_Source: `apps/multi-repo-plan-runner/.agents_workspace/DECISION_LOG.md`_

### Entry 1

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Implement docket from the SKELETON → ITER_01..03 plan to MVP.

**Context:** ITER_03 §04 specifies an atomic sidecar write via `os.replace` over the target.
On Windows a just-written target file is transiently locked by Defender/indexer, so an
immediate overwrite deterministically failed with `PermissionError (WinError 5)` in a
round-trip test (mark → reopen on the same plan). Plain `os.replace` to overwrite otherwise
works.
**Decision:** Kept the spec's atomic `os.replace` and added a bounded retry (10× @ 50ms) on
`PermissionError` in `tracker._atomic_write`. This preserves the crash-safety guarantee while
tolerating the platform's transient lock. Not a new dependency; ~6 lines.
**Impact / Risk:** Worst case a status write blocks up to ~0.5s before raising. Negligible for
a local single-user tool. No effect on POSIX where the lock doesn't occur.
**Outcome:** Round-trip test (mark/reopen/headless lifecycle/reset_stale_runs) passes.

### Entry 2

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Batch-implement instruction UX in both frontends (ITER_03 §05).

**Context:** The plan describes a per-plan, individually-editable instruction *panel* for batch
submit (browser) and an instruction prompt (TUI). A full inline multi-textarea panel is
significant UI code not core to the MVP behavior (per-plan distinct instructions).
**Decision:** Satisfied the functional requirement — distinct instruction per plan — with the
minimum UI: the browser collects each selected plan's instruction via sequential
`window.prompt` calls (each pre-filled with the resolved template), and the TUI uses a single
`InstructionModal` for single-implement plus per-plan default resolution for batch. Different
instructions per plan are still possible; the dedicated multi-row panel is deferred.
**Impact / Risk:** Less polished batch UX than the plan's panel; behavior (per-plan
instructions, per-project sequential, concurrent across projects, stop-on-failure) is fully
intact. Easy to upgrade to a panel later without touching core.
**Outcome:** Functional; not yet runtime-tested for a live headless run (requires the `claude`
CLI + `textual` installed).

### Entry 3

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Plan-compliance review (review-against-plan) of the ITER_03 MVP.

**Context:** SKELETON §02 lists `started_at` as a field of the in-memory `Run` record, but the
implemented `core.Run` dataclass omits it and no code path reads or sets a run start time.
**Decision:** Left `started_at` out rather than adding an unused field. It has no consumer in
the MVP (no elapsed-time display, no scheduling), so adding it would be dead code against the
write-less-code / YAGNI defaults. Recorded as a conscious spec deviation instead.
**Impact / Risk:** None functionally. If a future iteration surfaces run duration, add the
field then with its consumer.
**Outcome:** Documented; no code change.

### Entry 4

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Add a pytest suite at 100% coverage (user-requested).

**Context:** `tracker._atomic_write` retried `os.replace` with `for attempt in range(10): ... if
attempt == 9: raise`. The loop can never complete normally (it always returns on success or
raises on the 10th failure), leaving an unreachable branch that blocks 100% branch coverage.
**Decision:** Rewrote the retry as `for _ in range(9): try/except+sleep` followed by a final
bare `os.replace`. Behaviour is identical — 10 total attempts, 9 × 50ms sleeps between them, a
persistent `PermissionError` still propagates — but every branch is now reachable and tested.
Atomicity (temp-file + `os.replace`) and the Windows retry invariant are preserved.
**Impact / Risk:** None functional. Covered by `test_atomic_write_retries_then_succeeds` and
`test_atomic_write_gives_up_after_retries`.
**Outcome:** tracker.py at 100% line+branch coverage.

### Entry 5

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Add a pytest suite at 100% coverage (user-requested).

**Context:** The TUI test harness (`App.run_test()`) crashed on teardown with `'str' object has
no attribute '_close_messages'`. `DocketApp.__init__` stored the registry path in
`self._registry`, shadowing Textual's internal `App._registry` (the node set Textual iterates on
close). Masked in normal use because the process exits on quit, but a real latent bug.
**Decision:** Renamed the instance attribute to `self._registry_path` (3 occurrences in tui.py).
No behaviour change to docket; removes the framework-internal collision.
**Impact / Risk:** None — purely an internal rename. Enables the TUI to be driven under the
Textual test harness.
**Outcome:** tui.py at 100% coverage; clean app teardown.

### Entry 6

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Implement v2 plans (ITER_01_v2 config layering, ITER_02_v2 init/doctor/schema).

**Context:** `discover_repos` in ITER_02_v2 §04 derives the project name from `repo.name`
(unresolved). When `docket init --scan .` is run, the discovered repo at the scan root is
`Path(".")`, whose `.name` is `""` — an empty name that `load_registry` then rejects as
"missing 'name'". The plan also builds the `~`-relative path with `f"~/{p.relative_to(home)}"`,
which on Windows stringifies with backslashes.
**Decision:** Resolve the repo path first and take the name from the resolved path
(`p.name`), and emit the `~`-relative path with `.as_posix()`. For the normal `--scan ~/code`
case the names are identical to the plan's; only the degenerate "." root and the path separators
change. Strictly more robust, never worse; keeps generated configs portable and valid.
**Impact / Risk:** None negative. `init --scan .` now yields a valid non-empty name and
forward-slash paths.
**Outcome:** Verified via `docket init --scan . --dry-run`.

### Entry 7

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** "CI updated accordingly" (part of the v2 goal).

**Context:** The goal asked for CI to be updated for the v2 work but did not specify how.
`docket doctor` is positioned in ITER_02_v2 §04 as a CI gate, but its `claude_bin` PATH check
and per-project path checks fail in CI (no `claude`, project paths are local). Making it a hard
gate would red-X every CI run.
**Decision:** Keep the existing lint + test(100% coverage) jobs and add a single packaging
smoke step `uv run docket init --dry-run` to the test job. It exercises `_schema_path()` /
`importlib.resources` resolution of the shipped schema end to end — the real packaging risk that
unit tests (which may patch the path) can miss — and exits 0 without needing `claude`.
**Impact / Risk:** Minimal; one extra fast step. Did not wire `docket doctor` into CI for the
reason above.
**Outcome:** CI stays green; packaging of the schema asset is smoke-tested.

---

## apps/per-project-plugin-toggler

_Source: `apps/per-project-plugin-toggler/docs/claude_logs/DECISION_LOG.md`_

### Entry 001

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_03 — `_parse_skill_frontmatter` fallback for agent files

**Context:** The plan says to reuse `_parse_skill_frontmatter` unchanged for agents. But the existing fallback is `path.parent.name`, which gives "agents" (the directory name) when called with an agent `.md` file path, not the file stem (e.g. `my-agent`).

**Decision / Action:** Added optional `fallback` parameter to `_parse_skill_frontmatter`. When absent it defaults to `path.parent.name` (existing behaviour for skills). `load_plugin_agents` passes `md_file.stem` explicitly.

**Rationale:** Minimum-change fix that keeps skills behaviour identical while giving agents the correct name. The JS version already used explicit fallback names in `parseSkillFrontmatter(text, stem)`.

**Impact / Risk:** Low — the change is backward-compatible. Only agent loading uses the new parameter.

**Outcome:** `_parse_skill_frontmatter` signature changed; all call sites updated.

---

### Entry 002

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_03 — Spurious `localIds.add(pluginId)` in plan draft for extension.js

**Context:** The plan's `loadInstalledPlugins` JS pseudocode contains `localIds.add(pluginId)` referencing a `localIds` Set that is never declared. It appears to be a leftover from an earlier draft and has no downstream usage in the plan.

**Decision / Action:** Dropped the line. The `local` and `global` arrays are returned directly; no intermediate Set is needed.

**Rationale:** The line would cause a ReferenceError at runtime. The downstream `buildPluginList` and `_onMessage` functions build local ID sets independently where needed.

**Impact / Risk:** None — the line was dead code in the plan.

**Outcome:** `loadInstalledPlugins` in extension.js omits the spurious line.

---

### Entry 003

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_03 — Keep `_send_json` name in server.py (plan used `_respond_json`)

**Context:** The plan's handler snippets use `self._respond_json(payload)`. The existing codebase uses `self._send_json`. Renaming would be no-value churn.

**Decision / Action:** Kept `_send_json` throughout server.py.

**Rationale:** Rename has zero functional value and increases diff noise. Existing name is clear.

**Impact / Risk:** None.

**Outcome:** `_send_json` retained.

---

### Entry 004

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_03 — `toggleSkills` renamed to `toggleDisclosure` with `data-label` attribute

**Context:** The plan reuses `toggleSkills` for agents, but the function hardcodes "skill" in the button label. Without a label hint, toggling an agents disclosure would show "N skills" incorrectly.

**Decision / Action:** Renamed `toggleSkills` to `toggleDisclosure` in both HTML files. Added `data-label="skill"` / `data-label="agent"` to the toggle buttons so the function reads the correct noun.

**Rationale:** Minimum change to support both disclosures with correct labels. No new CSS needed.

**Impact / Risk:** Low — internal function rename within the same files. No external callers.

**Outcome:** Both HTML files use `toggleDisclosure`; skills and agents show correct labels.

---

### Entry 005

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_04/05/06 — Rename `load()` to `fetchPlugins()` in index.html

**Context:** The ITER_04 plan references `fetchPlugins()` in `installPlugin()` and `connectEventStream()` but the existing codebase had a single `load()` function. The plan did not include a rename directive.

**Decision / Action:** Renamed `load()` to `fetchPlugins()` directly in index.html and updated all call sites. Did not create a wrapper alias — the rename is clean and there are no external callers.

**Rationale:** `fetchPlugins` is the name used throughout the new plan code. Keeping `load()` and adding an alias would leave dead names in the file with no benefit.

**Impact / Risk:** Low — purely internal to index.html.

**Outcome:** `load()` → `fetchPlugins()` in index.html; `load()` still works in index.html because project-apply handler previously called `load()` — updated to `fetchPlugins()` + `fetchMarketplace()`.

---

### Entry 006

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_05 — Sync VSCode styles.css diverged from canonical HTML styles.css

**Context:** Before ITER_05, `vscode-extension/webview/styles.css` had accumulated classes (`.project-picker`, `.mock-banner`) not present in `html/styles.css`, and was missing classes added in ITER_03 (`html/styles.css` is the more up-to-date file). ITER_05 designates `html/styles.css` as the canonical source.

**Decision / Action:** Replaced `vscode-extension/webview/styles.css` with the full content of `html/styles.css` (which now includes all ITER_04+05+06 additions). The old VSCode-only classes were dead code — no `panel.html` elements referenced them.

**Rationale:** ITER_05 explicitly states the VSCode file "becomes a generated file — never edit it directly." Preserving the dead VSCode-only classes would contradict this and add noise.

**Impact / Risk:** Low — verified no `panel.html` elements use `.project-picker` or `.mock-banner`.

**Outcome:** `vscode-extension/webview/styles.css` is now identical to `html/styles.css`.

---

### Entry 007

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_04 — `installPlugin()` in panel.html does not wait for a result message

**Context:** The plan says the VSCode webview posts `{ type: 'install' }` and then waits for the next `{ type: 'load' }` message to re-render. The button stays in "Installing…" state until that arrives. This is correct per spec. However, the plan also notes "No separate `{ type: 'installResult' }` message."

**Decision / Action:** `installPlugin()` in panel.html sets the button to "Installing…" and posts to the extension, then returns. The button stays in that state until the extension calls `_refresh()` which posts `{ type: 'load' }` — which triggers a full re-render and resets the button state.

**Rationale:** Exactly per spec. The full-refresh approach keeps webview stateless with respect to install outcomes.

**Impact / Risk:** None — matches the specified behaviour exactly.

**Outcome:** Implemented as described.

---

### Entry 008

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_07 — `installLocalPlugin()` calls `/api/install` which is removed

**Context:** ITER_07 removes `POST /api/install` entirely and replaces it with `POST /api/install-stream`. The `installLocalPlugin()` function in `index.html` (used for orphan plugins in the local list) still called `/api/install`. The plan does not mention updating this function.

**Decision / Action:** Updated `installLocalPlugin()` to call `/api/install-stream` using the same `ReadableStream` SSE parsing pattern. Line events are consumed silently (no per-row log area on local plugin rows). Only the `done` event is checked for errors. No log area is shown — the button state and top-level `showError()` are used instead.

**Rationale:** The old endpoint is gone; keeping `installLocalPlugin()` calling it would cause a 404 at runtime. The minimal fix is to use the new endpoint with graceful stream consumption. Adding a log area to local plugin rows would exceed ITER_07 scope.

**Impact / Risk:** Low — same user-visible behaviour as before (button spins, error shown on failure, list refreshes on success). Only internal call site changes.

**Outcome:** `installLocalPlugin()` updated in `index.html`.

---

### Entry 009

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-15T00:00:00Z
**Task:** ITER_08 — `package.json` `repository.url` placeholder

**Context:** The ITER_08 spec shows `"url": "https://github.com/<your-org>/skills-toggle"`. The actual repo URL is not specified in the plan.

**Decision / Action:** Used `https://github.com/cheneeheng/skills-toggle` based on the git user handle `cheneeheng` visible in git config. The `publisher` field is set to `ceh-plugins` as specified.

**Rationale:** The plan uses `<your-org>` as a placeholder; `cheneeheng` is the most reasonable inference from the repo context. This is not load-bearing for local `.vsix` installs — `vsce package` only validates the field is non-empty.

**Impact / Risk:** Low — only affects `.vsix` metadata, not functionality. Can be corrected before any Marketplace publish.

**Outcome:** `repository.url` set to `https://github.com/cheneeheng/skills-toggle`.

---

### Entry 010

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-24T00:00:00Z
**Task:** ITER_12 — Helper method names in `/api/uninstall-stream`

**Context:** The ITER_12 plan references `self._respond_json(...)` and `self._read_json_body()` in the new handler. The existing `server.py` (including the sibling `/api/install-stream` handler) uses `self._send_json(...)` and `self._read_body()`.

**Decision / Action:** Used the existing method names `_send_json` and `_read_body` in the new handler. Did not rename or add aliases.

**Rationale:** Minimum-change bias. The plan's names appear to be a drafting slip — every other handler in the file uses the existing names, and matching them keeps the new code consistent without an unrelated rename pass.

**Impact / Risk:** None — purely a naming alignment.

**Outcome:** `/api/uninstall-stream` calls `_send_json` for validation errors and `_read_body()` for the request body.

---

### Entry 011

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-24T00:00:00Z
**Task:** ITER_12 — Frontend HTML-escape helper name

**Context:** The plan's `renderMpPluginRow` snippet calls `escapeHtml(p.id)`. The existing codebase (both `html/index.html` and `vscode-extension/webview/panel.html`) defines and uses `esc(...)` for the same purpose; `escapeHtml` is not defined anywhere.

**Decision / Action:** Used `esc(...)` instead of `escapeHtml(...)` in the updated marketplace row markup in both surfaces.

**Rationale:** Plan terminology drift. Introducing `escapeHtml` as an alias would be a non-requested refactor.

**Impact / Risk:** None — functionally identical.

**Outcome:** Updated marketplace rows use the existing `esc()` helper.

---

### Entry 012

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-24T00:00:00Z
**Task:** ITER_12 — Error handling in `/api/uninstall-stream`

**Context:** The plan's snippet wraps the entire flow in a single broad `try/except` with `BrokenPipeError` and a generic `Exception`. The existing `/api/install-stream` handler uses a tighter pattern: a dedicated `try/except FileNotFoundError` for `Popen` (to report a missing `claude` CLI as a `done` event), then a separate `try/except (BrokenPipeError, ConnectionResetError)` around the stdout-read loop that kills the subprocess on client disconnect.

**Decision / Action:** Mirrored the existing install-stream error-handling structure exactly rather than the plan's looser version.

**Rationale:** The plan explicitly says "exact mirror" of `/api/install-stream`. The existing handler's structure is stricter and handles the "claude CLI missing" case as a stream event (better UX than dropping the connection), so mirroring it is more faithful to the plan's stated intent than copying its inline snippet verbatim.

**Impact / Risk:** Low — both surfaces of the install path already use this pattern; no new behaviour was introduced.

**Outcome:** Uninstall stream handles `FileNotFoundError`, `BrokenPipeError`, and `ConnectionResetError` identically to install stream.

---

### Entry 013

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-05-24T00:00:00Z
**Task:** ITER_12 — `uninstallPlugin()` in `panel.html` not shared with `index.html`

**Context:** The plan describes `uninstallPlugin()` as "a single shared function (both surfaces)" with a VSCode guard at the top that posts a message and returns. The existing codebase does not actually share files between the two surfaces — `installPlugin()` is implemented separately in `html/index.html` (full SSE body) and `vscode-extension/webview/panel.html` (a thin `vscodeApi.postMessage` shim).

**Decision / Action:** Followed the existing per-surface split: `html/index.html` got the full SSE consumer body; `panel.html` got a thin `uninstallPlugin(id, scope)` that just posts `{ type: 'uninstall', id, scope }`.

**Rationale:** No file-sharing mechanism exists between `html/` and `vscode-extension/webview/`; the "shared function" framing in the plan is aspirational. Matching the existing `installPlugin` split keeps diffs minimal and consistent.

**Impact / Risk:** None — behaviour is identical to what the plan describes; only the duplication pattern differs.

**Outcome:** `uninstallPlugin` exists in both files, mirroring how `installPlugin` is structured today.

---

### Entry 002

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-06T00:00:00Z
**Task:** ITER_13–17 — bulk Enable/Disable scope

**Context:** The three-scope model (ITER_13) splits plugins into Local/Project/User, but the pre-existing "Enable all / Disable all" bulk buttons predate it and the plans never address how bulk interacts with three scopes.

**Decision:** Bulk toggle operates on the **Local** section only — the lowest-blast-radius scope and the only one writable before this work. Project/User bulk flips would touch committed/cross-project state and the plans do not request it.

**Impact / Risk:** Bulk no longer affects Project/User rows (it never reached them before either). In VSCode, each bulk toggle still routes through the per-toggle confirmation added by ITER_14 (non-modal for Local), so "Enable all" can prompt once per Local plugin. Acceptable; a single batched-confirm path was out of scope.

---

### Entry 003

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-06T00:00:00Z
**Task:** ITER_17 — marketplace install-state source

**Context:** ITER_17 introduces a per-id `installedScopes` map and says to put it on the `/api/plugins` (or marketplace) payload. The HTML server has a separate `/api/marketplace` endpoint that previously annotated each plugin with single `installed`/`installedScope` fields.

**Decision:** `installedScopes` is emitted only on `/api/plugins`; the per-plugin `installed`/`installedScope` annotation was removed from `build_marketplace_response`. The frontend's marketplace panel reads the global `installedScopesMap` (set on every plugins fetch) to decide per-scope install vs. installed tags.

**Impact / Risk:** The marketplace panel now depends on a prior `/api/plugins` load for install state. Initial load fetches both; the panel starts closed and re-renders on plugins load, so the map is always populated before display. Element-id helper naming also deviated from the plan's single `sectionEls` (split into `sectionInstallEls`/`sectionUninstallEls` + runtime `mpScopeVal`) to avoid embedding CSS.escape output into onclick string literals.

---

### Entry 014

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-07T00:00:00Z
**Task:** Smoke test coverage scope after three-scope migration

**Context:** The existing smoke tests (and fixtures) asserted the removed `global`/`pluginScope` contract and POSTed `/api/toggle` without the now-required `scope` — they fail against current `server.py`. Asked to "cover all the different possible cases," but several endpoints/paths cannot be exercised safely or deterministically: `/api/install-stream`, `/api/uninstall-stream`, `/api/marketplace-refresh` shell out to the real `claude` CLI; user-scope toggle writes the real `~/.claude/settings.json`.

**Decision:** Rewrote fixtures + `smoke.sh`/`smoke.ps1` for the three-scope model. Covered: `/api/plugins` shape, three-scope bucketing, cross-project exclusion (added a `smoke-other` fixture entry under a different `projectPath`), row fields, enabled defaults, `installedScopes`, mock fallback; `/api/toggle` happy paths for local + project plus all four 400 validations; `/api/marketplace` shape; `/api/set-project` invalid-path 400. Excluded the three CLI-streaming endpoints and any user-scope *write*; user scope is verified read-only. Used containment (not exact equality) for the user bucket and mock-mode sections because `build_sections` unions installed plugins with settings and `load_settings_user` reads the real home file.

**Impact / Risk:** Tests are CI-oriented (fresh runner home). Locally they still overwrite then delete `~/.claude/plugins/installed_plugins.json` (pre-existing destructive cleanup) — flagged to the user; not auto-fixed. Streaming endpoints remain unverified by smoke tests.

**Outcome:** `bash -n` and PowerShell parser both pass; not executed locally to avoid clobbering the real plugin registry.

---

### Entry — ITER_18 mock-notice retint

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-07T00:00:00Z
**Task:** ITER_18 §05 — `.mock-notice` retint

**Context:** §05 says retint `.mock-notice` to the teal/terracotta neutrals and "keep its data-theme / data-context triad." The original triad existed because the colours were hardcoded hex per context. The redesign is token-driven.
**Decision:** Retinted `.mock-notice` to the terracotta brand family using `var(--accent-wash)`/`var(--accent-hi)`/`var(--accent)`, which auto-adapt across light/dark/vscode from a single rule. Collapsed the former three-block triad to one block (kept one small `:root[data-context="vscode"]` override forcing readable `--fg` text). This honours "retint to teal/terracotta neutrals" while avoiding redundant per-context blocks that tokens make unnecessary.
**Impact / Risk:** Behaviour change for the VSCode mock notice — it now reads as the terracotta brand rather than deferring to `--vscode-inputValidation-warning*`. Consistent with the redesign intent.

---

### Entry — ITER_18 rise animation target

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-07T00:00:00Z
**Task:** ITER_18 §05 — `@keyframes rise` application

**Context:** §05 specifies the `rise` entrance animation on "header/card/rows" AND a row hover-lift (`transform: translateY(-2px)`). A persistent animation with `fill: both` pins the animated `transform` in the cascade, which would defeat the hover-lift `transform` on the same `.plugin-row`.
**Decision:** Applied `rise` to `header`, `.project-card`, and the three section containers (`#local-section/#project-section/#user-section`) with a staggered `animation-delay` — not to individual `.plugin-row` elements. Rows rise visually with their section while keeping a working hover-lift.
**Impact / Risk:** Rows do not individually stagger; they fade in as a section group. Hover-lift preserved. No functional risk.

### Entry 015

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-09T00:00:00+08:00
**Task:** ITER_19 — JS extraction scope ("move the script out into smaller js files")

**Context:** The user asked to extract the inline script "for the html files". Two HTML files exist: html/index.html and vscode-extension/webview/panel.html. Extracting panel.html's script requires extension.js changes (webview URI substitution), which ITER_19 explicitly freezes ("extension.js unchanged").
**Decision:** Extracted html/index.html only, into eight classic scripts under html/js/ plus a path-safe /js/*.js route in server.py. panel.html's script left inline.
**Impact / Risk:** If the user also meant the webview, a follow-up touching extension.js is needed.
**Outcome:** html/ surface now serves js/state.js, helpers.js, theme.js, render.js, install-panel.js, api.js, events.js, main.js in order.

### Entry 016

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-09T00:00:00+08:00
**Task:** ITER_19 §04 — marketplace icon vs pre-existing package.json "icon" field

**Context:** The plan says the "icon" field is "added", but package.json already had "icon": "icon.png" with a committed root icon.png (from ITER_08).
**Decision:** Followed the ITER_19 spec: generated vscode-extension/media/icon.png per the asset spec, re-pointed the field to media/icon.png, and deleted the superseded root icon.png (recoverable from git history).
**Impact / Risk:** None expected; .vscodeignore does not exclude media/ (R5 verified).
**Outcome:** New 128x128 brand-tile icon committed in media/.

### Entry 017

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-09T00:00:00+08:00
**Task:** ITER_19 §05 — dense-list details the spec left implicit

**Context:** The spec converts .plugin-row from cards to "flat list items separated by hairline dividers" but does not mention the .plugin-list gap (0.4rem) or the row's full border.
**Decision:** Removed the inter-row gap and the full border (kept only border-bottom); with gaps/cards, hairline dividers would not read as a list. Also took the §05 mono-element rule literally for .marketplace-badge (11px, color fg-muted) while leaving its teal border/wash, since only "color" is named.
**Impact / Risk:** Marketplace badge now has muted text inside a teal-bordered chip; flag for visual QA.
**Outcome:** Dense list renders with dividers; enabled wash + edge unaffected.

### Entry 018

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-09T00:00:00+08:00
**Task:** ITER_19 review — `.skills-toggle-btn:hover` listed as a `--secondary-hi` consumer

**Context:** The §02 token table says `--secondary-hi` is "the flat hover fill for filled controls (`.mp-install-btn:hover`, `.bulk-install-btn:hover`, `.skills-toggle-btn:hover`)". But `.skills-toggle-btn` is not a filled control — it is a borderless text-link button (`background: none`) and had no hover rule in the implemented ITER_18 file. §05's operative instruction only says to *re-point existing* gradient/`-glow` filled-button hovers, of which there were two.
**Decision:** No CSS change. The §02 parenthetical is drafting drift (it assumes the button is filled); inventing a `--secondary-hi` fill hover for a text-link button would be a visual change §05 never specifies.
**Impact / Risk:** None — matches ITER_18 behaviour. If a hover affordance is wanted on the disclosure button, it should be specified in a future iteration.

### Entry 019

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-10T00:00:00+08:00
**Task:** Extract brand-mark SVG to a file; reference it in both surfaces

**Context:** Request 2 asked to add the logo next to the webview title "like the HTML version", but panel.html already had the identical inline mark (f1b94e8). Also had to pick a reference mechanism that keeps the mark theme-reactive: <img> freezes colours because CSS custom properties do not resolve inside an image document.
**Decision:** Interpreted request 2 as "source the mark from the SVG file". HTML surface: external <use href="/icon.svg#mark"> (same-origin, page vars cascade into the use shadow tree) + new /icon.svg route. Webview: external <use> is cross-origin-blocked, so extension.js inlines webview/icon.svg via an __ICON_SVG__ placeholder. icon.svg fills use var(--x, fallback) so the same file doubles as the favicon.
**Impact / Risk:** Two copies of icon.svg (html/ and vscode-extension/webview/) with no sync step, unlike styles.css. External <use> requires a modern browser (all evergreen browsers OK).
**Outcome:** Pending user verification in browser and Extension Development Host.

---

## tools/scheduled-session-digests

_Source: `tools/scheduled-session-digests/docs/claude_logs/DECISION_LOG.md`_

### Entry 1

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-15T21:58:00+08:00
**Task:** Add interactive skills (daily-lessons, daily-summary, weekly-lessons) replacing the `claude --print` cron triggers, which break under the new programmatic-credit limit.

**Context:** Two forks the user left unresolved:
1. The daily-lessons subagents run in parallel and share the meta-repo working dir. The `ceh-lessons-learned` skill writes to a fixed relative path (`docs/claude_logs/LESSONS_LEARNED.md`), so reusing it across parallel subagents would collide.
2. Where to stage the per-chat input files / manifest, and whether to use subagents for the weekly harvest.

**Decision:**
1. The daily-lessons SKILL.md embeds the lessons-learned methodology and instructs each subagent to write directly to its own unique output path, instead of invoking `ceh-lessons-learned`. This makes the fan-out parallel-safe. daily-summary was already parallel-safe (its prompt writes to a per-job Output path).
2. Staging goes in `$CLAUDE_META_DIR/.claude/scheduler-jobs/<scheduler>/` (input files + `manifest.json`); the prepare scripts add `.claude/scheduler-jobs/` to the meta repo `.gitignore` so a partial run is never committed. Weekly uses no subagents — it is a single analysis job, per the user.

**Impact / Risk:** The daily-lessons output format is now defined in SKILL.md rather than delegated to the `ceh-lessons-learned` skill; if that skill's format evolves, the SKILL.md must be updated to match. Low risk — format is stable and self-contained.

**Outcome:** Six prepare scripts (.sh + .ps1) and three SKILL.md files created; all pass syntax/parse checks and the no-work path was smoke-tested on both platforms.

---

## automation-suite

_Source: `docs/automation-suite-decision-log.md`_

### Entry 001

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-10T00:00:00+02:00
**Task:** Update dashboard.css to follow the styling in tmp.css

**Context:** tmp.css styles a different component set (plugin manager), so "follow the styling" could not mean copying rules 1:1. It also omits the Google Fonts @import (VSCode CSP) and lacks tokens the dashboard JS/markup depend on.
**Decision:** Adopted tmp.css's design language and foundation: radius token hierarchy (--radius-lg/md/sm), --shadow-sm as the only shadow, no atmosphere/glow/hover-lift, secondary-teal hover states, tmp.css's theme-btn and section-title styles. Kept the font @import (standalone HTML page), the semantic chart colors, the legacy alias layer, and --accent-hi (read by dashboard.js for chart hover). Skipped the VSCode bridge block (dashboard never runs in a webview).
**Impact / Risk:** Visual-only changes; cards lose hover lift and glow shadows, hovers shift from terracotta to teal. No markup or JS changes.
**Outcome:** dashboard.css rewritten; grep confirmed no remaining references to dropped tokens.

### Entry 002

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-16T00:00:00+02:00
**Task:** Refactor the dashboard server — separate the two data sources, add a README

**Context:** User chose "Restructure modules"; the option preview depicted a nested `dashboard/` package (session_stats.py, live_statusline.py, merge.py, README.md). But `dashboard_server.py` loads the static assets via `Path(__file__).parent / dashboard.html`, and the scheduled-task launcher runs `cc-statusline-dashboard-server.py` from this exact folder with sibling-module imports on sys.path. A nested package would force asset-path and import-path rewrites for no functional gain.
**Decision:** Kept the new modules flat in the existing folder rather than nesting them in a `dashboard/` subpackage. Split `dashboard_data.py` into `session_stats.py` (transcripts → tokens + estimated cost), `live_statusline.py` (statusline logs → rate limits + actual cost), and `merge.py` (reconciliation + payload). Moved `build_payload` out of `dashboard_server.py` into `merge.py`; deleted `dashboard_data.py`. The semantic outcome (three separated modules + README) matches the user's selection.
**Impact / Risk:** No behavior change except a ~1e-12 float-ordering difference in `by_model` cost (per-session grouping of the four cost terms instead of one streamed accumulator); invisible after 2-decimal formatting. Asset loading and launch path untouched.
**Outcome:** All modules byte-compile; payload output verified equal to the original for sessions and live data, and equal-to-rounding for stats, against real ~/.claude data.
