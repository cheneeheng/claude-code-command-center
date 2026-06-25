# Decision Log

---

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

**Decision / Action:** Used `https://github.com/cheneeheng/skills-toggle` based on the git user name `EeHeng Chen` (handle `cheneeheng`) visible in git config. The `publisher` field is set to `ceh-plugins` as specified.

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
