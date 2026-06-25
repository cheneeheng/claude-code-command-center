# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.1] - 2026-06-12

### Fixed
- Webview brand mark missing in packaged installs: the single-occurrence `__ICON_SVG__` string replace in `extension.js` matched the token inside the explanatory HTML comment instead of the `<h1>` placeholder, leaving the literal token in the header. The comment no longer contains the token and the replace is now global with a function replacement (guards `$`-patterns in the SVG)

## [0.9.0] - 2026-06-10

### Changed
- Tidewater de-generification (ITER_19): stripped the ITER_18 garnish layer (atmosphere, gradients, glows, entrance motion, hover-lift, uniform radii) while keeping the palette, colour roles, and VSCode bridge — the terracotta enabled-edge is now the single decorated element. Adds the two-tone fader mark to both headers and a generated marketplace icon (`media/icon.png` supersedes the ITER_08 root `icon.png`) (f1b94e8)
- Inline scripts of both surfaces extracted into small classic JS files (`html/js/*`, `vscode-extension/webview/js/*`); `server.py` gains a path-safe `/js/` route and `extension.js` substitutes `__JS_BASE__` (f1b94e8)
- Brand mark extracted to a shared `icon.svg` per surface, replacing the inline header SVG and data-URI favicon — the HTML page references it via external `<use>` (theme-reactive, doubles as favicon via `var()` fallbacks), the webview inlines it through an `__ICON_SVG__` placeholder; `html/icon.svg` is canonical and synced by `make sync-css` (6d7f5d5)

### Fixed
- `scripts/sync-css.ps1` paths anchored to the script root so the npm `prepackage` hook works when invoked from `vscode-extension/` (6d7f5d5)

## [0.8.0] - 2026-06-07

### Changed
- Tidewater visual redesign (ITER_18): replaced the flat blue-accent palette with a teal/terracotta complementary system — teal drives all interactive controls, terracotta marks the enabled-row state, the logo mark, and the mock notice. Adds depth (shadows/radii), web fonts (Fraunces / Hanken Grotesk / JetBrains Mono in the HTML surface), a `rise` entrance animation, and a static logo mark. The VSCode surface uses a hybrid bridge — neutrals derive from `--vscode-*`, brand colours hardcoded — and keeps editor fonts (CSP). No data-model, endpoint, or webview-message logic changes (d5791fb)

## [0.7.0] - 2026-06-07

### Added
- Three-scope plugin model: plugins are grouped into Local, Project, and User scopes, each backed by its own settings file, with per-scope toggle and install/uninstall (fa533dd)
- `skillsToggle.confirmActions` VSCode setting (default `false`) to gate the enable/disable and uninstall confirmation dialogs — actions apply immediately unless opted in (573b4c3)

### Fixed
- Streamed install/uninstall result log now stays visible for 3s before the plugin row refreshes, in both the HTML and VSCode surfaces — previously the uninstall row (and its log) vanished instantly (573b4c3)

### Chore
- Smoke tests and fixtures rewritten for the three-scope model with expanded coverage: scope bucketing, cross-project exclusion, toggle validations, marketplace/set-project, and mock fallback (573b4c3)

## [0.6.1] - 2026-05-30

### Fixed
- Expanded skills/agents list now scrolls instead of clipping plugins with many entries — `overflow-y: auto` added to the open `.skills-list` (9f8163a)

## [0.6.0] - 2026-05-25

### Added
- Install/Uninstall toggle on marketplace plugin rows in both HTML and VSCode surfaces — streams progress output inline (2eb1138)
- MIT `LICENSE` and marketplace-oriented `README.md` added to the VSCode extension for Marketplace publication (766191b)
- HTML and VSCode user guides (`docs/user-guide-html.md`, `docs/user-guide-vscode.md`) (33b2186)

### Fixed
- Drive letter normalized to uppercase in VSCode `projectRoot` to prevent path-matching failures on Windows (fbcbf80)
- Uninstall for Claude Code-managed plugins now resolves the correct uninstall path on Windows (b6093fd)
- Scope passed to uninstall now read from `installed_plugins.json` instead of being hard-coded to `global` (9127499)
- Install/uninstall broken on Windows due to drive-letter case mismatch and incorrect path separator handling (4cd9c8f)
- Install/uninstall log area no longer hangs — delay added between stream open and first write (4a2a0f4)

## [0.5.0] - 2026-05-16

### Added
- GitHub Actions CI pipeline with lint, smoke tests, and automated release workflow (b1b4e4e)

### Fixed
- ESLint configured to support ES2022 class fields (`ecmaVersion: 2022`) and the `vscode` module as a known global (1ca816c)

### Chore
- Bump GitHub Actions runners and action versions to latest major (2233fdb)

## [0.4.0] - 2026-05-15

### Added
- Marketplace panel with SSE-streamed installs — `/api/install-stream` replaces `/api/install`; install output shown line-by-line in an inline log area (de12865)
- Uninstall flow for locally-installed plugins in both HTML and VSCode surfaces (de12865)
- VSCode webview parity with HTML surface: install/uninstall panel, streaming log area, and marketplace dropdown (de12865)
- Orphan plugins (present in `settings.json` but absent from `installed_plugins.json`) now appear with an Install button instead of a broken toggle (de12865)
- Auto-sync on startup: installed plugins missing from `settings.json` are added with `enabled: true` (de12865)
- Makefile and PowerShell scaffolding for VSCode extension packaging (de12865)
- VSCode extension icon (`icon.png`) for marketplace display (ec451c3)

### Fixed
- Install button and marketplace dropdown overflow at narrow panel widths (de12865)
- `ConnectionAbortedError` (Windows WinError 10053) now caught in SSE handler alongside `BrokenPipeError` (de12865)
- Plugin install error message now surfaces the actual failure reason from the CLI (de12865)
- Remove install confirmation popup in VSCode extension — installs proceed immediately on click (4dffec1)

### Chore
- Add `*.vsix` to `.gitignore` so packaged extension artifacts are not tracked

## [0.3.0] - 2026-05-15

### Added
- Marketplace panel with SSE-streamed installs — `/api/install-stream` replaces `/api/install`; install output is shown line-by-line in an inline log area (8bd7d91)
- Uninstall flow for locally-installed plugins in both HTML and VSCode surfaces (8bd7d91)
- VSCode webview parity with HTML surface: install/uninstall panel, streaming log area, and marketplace dropdown (8bd7d91)
- Orphan plugins (present in `settings.json` but absent from `installed_plugins.json`) now appear with an Install button instead of a broken toggle (09a8d29)
- Auto-sync on startup: installed plugins missing from `settings.json` are added with `enabled: true` so both files stay in sync without manual intervention (09a8d29)
- Makefile and PowerShell scaffolding for VSCode extension packaging (8bd7d91)

### Fixed
- Install button and marketplace dropdown overflow at narrow panel widths — `minmax(0,1fr)` grid column and `flex:1;min-width:0` on the select element (c18c31f)
- `ConnectionAbortedError` (Windows WinError 10053) now caught in SSE handler alongside `BrokenPipeError` (c18c31f)
- Plugin install error message now surfaces the actual failure reason from the CLI (9f4a857)

## [0.2.0] - 2026-05-15

### Added
- Load agents from `.md` files under `agents/` directory per plugin, displayed in a dedicated agents disclosure alongside skills (271f647)
- Version badge per plugin row showing the installed plugin version (271f647)
- Global badge on global-scope plugin rows to distinguish scope visually (271f647)
- Collapsible path picker (HTML) and card header (VSCode) in the redesigned project card (271f647)

### Changed
- Refactor plugin loading to return `{ local, global }` arrays based on scope and `projectPath` matching, replacing the previous inherited/scope terminology (271f647)
- Toggle disclosure label uses `data-label` attribute (renamed `toggleSkills` to `toggleDisclosure`) to display the correct noun per section (271f647)
- Guard toggle endpoint to reject non-local plugin IDs (271f647)
- Mock plugin structure updated to match `{ local, global }` shape of real data (271f647)

### Fixed
- Skip skill folders that lack a `SKILL.md` file in both `server.py` and `extension.js` (72ca34b)
- Remove redundant global badge from global plugin rows; section heading already conveys scope (72ca34b)
- Align version badge styling to match marketplace badge using shared design tokens (72ca34b)
- Remove `margin-left`/`vertical-align` from version badge to fix column-layout indent (72ca34b)

## [0.1.0] - 2026-05-14

### Added
- Collapsible skill list per plugin row with skill count shown in the disclosure toggle (6d11f43)

### Changed
- Skill path resolution now prefers `installPath` from `installed_plugins.json` over the legacy `marketplaces/<mp>/<name>/skills/` fallback (d11ee0e)
- Toggle confirmation dialog removed; state is written immediately on change (d11ee0e)

### Fixed
- Resolve correct plugin skills directory layout when scanning installed plugins (484172b)

## [0.0.2] - 2026-05-14

NOTE: Should have been 0.1.0 due to new features added.

### Added
- Shared CSS design tokens (`--toggle-on`, `--btn-danger`) applied across HTML and VSCode surfaces (c346d53)
- VSCode sidebar launcher — `Skills: Manage Plugins` registers as a sidebar view (c346d53)
- Section descriptions below Local and Inherited headings explaining each tier (5070d2c)
- `/api/shutdown` endpoint and Stop server button in HTML header for graceful shutdown (5070d2c)
- `start.sh` / `start.bat` / `start.ps1` convenience launcher scripts for the HTML server (c346d53)

### Changed
- Inherited plugin row simplified: removed disabled toggle and `global default` badge; CTA renamed from "Override locally" to "Localize" (5070d2c)
- Plugin name truncation replaced with `word-break: break-word` so long names wrap instead of clip (5070d2c)
- Plugin info layout changed from horizontal to vertical (name above marketplace badge) (5070d2c)
- Theme toggle moved into flex header row alongside title and Stop server button (5070d2c)
- Active toggle color changed from `--accent` to dedicated `--toggle-on` green token (5070d2c)
- VSCode sidebar refreshes automatically on panel visibility change (5070d2c)
- Inherited plugin tier shown in UI using global default state with Localize CTA (c346d53)

## [0.0.1] - 2026-05-14

### Added
- Implement HTML server (`server.py`) using stdlib only — no pip dependencies (ab4fad2)
- Implement VSCode extension with webview panel and `Skills: Manage Plugins` command (ab4fad2)
- Fall back to `MOCK_PLUGINS` when `installed_plugins.json` is absent, with `"mock": true` in API response (ab4fad2)
- CORS restriction in `server.py` to `http://localhost` only (ab4fad2)

### Fixed
- Parse plugins from dict keys instead of a list to match the actual `installed_plugins.json` schema (61ee55e)
- Remove toggle confirmation dialog from VSCode extension to streamline UX (61ee55e)
- Surface JSON parse errors to the caller instead of crashing silently (2d55100)

[Unreleased]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.0.2...v0.1.0
[0.0.2]: https://github.com/cheneeheng/claude-code-plugin-toggler/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/cheneeheng/claude-code-plugin-toggler/releases/tag/v0.0.1
