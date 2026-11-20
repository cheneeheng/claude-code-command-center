# Changelog

All notable changes to the per-project-plugin-toggler are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are tagged `pppt-vX.Y.Z` (see [`docs/releasing.md`](../../docs/releasing.md)).
Development through 0.9.x predates this monorepo and happened in a previous repository;
this log starts at the first release tracked here.

## [Unreleased]

### Added
- Multi-root workspace support in the VSCode extension: with two or more workspace folders
  open, the PROJECT card becomes a dropdown of the folders, and the panel works on the one
  you pick (plugins, settings, and install/uninstall/marketplace refresh). The choice is
  remembered per workspace. A single-folder window keeps the fixed card.

### Changed
- Read and write the user settings and the plugin registry under `CLAUDE_CONFIG_DIR` when
  it is set, as Claude Code does, instead of always `~/.claude`.
- Show the empty state when `installed_plugins.json` does not exist. The panel used to
  show two mock plugins with a notice.

### Removed
- Archive the browser version (HTML page and Python server), with its smoke tests and CSS
  sync scripts, under `archive/`: it is no longer built or tested, and the VSCode extension
  is the only surface. Edit `webview/styles.css` and `webview/icon.svg` directly.

### Fixed
- Stop a toggle from replacing a malformed `.claude/settings.json` or `~/.claude/settings.json`
  with only `enabledPlugins`: a settings file that does not parse is now left untouched at
  every scope, and the panel shows the error.
- Show an error when a toggle cannot be saved, instead of silently flipping the toggle back.
- Save settings through a temp file and a rename, so a write that fails midway no longer
  leaves a truncated settings file.
- Ignore a toggle message whose plugin id or enabled value has the wrong type.
- Read a skill or agent description in full when its file has CRLF line endings. A
  block-scalar description showed as `>-`.
- Skip a skill or agent file that cannot be read, instead of putting the whole panel in
  its error state.
- Match a project's plugins when its path differs only in letter case, on Windows and macOS.
- Say that the `claude` CLI was not found on `PATH`, instead of only `Exit code 1`.
- Stop a `claude` call that is still running when the panel is closed.

### Security
- Run only a `claude` found on `PATH`. On Windows a `claude.cmd`, `claude.bat` or
  `claude.exe` in the project folder could run in its place.
- Refuse a plugin id that starts with a dash, which the CLI would read as an option.
- The VSCode extension now watches the user settings and `installed_plugins.json` even when
  the window had no folder open when the panel was first shown.
- A malformed `.claude/settings*.json` no longer leaves an unhandled error behind a toggle;
  the panel shows the error with the folder's name.

## [0.10.0] - 2026-10-03

### Added
- Search box under the marketplace picker in the install panel. It filters the selected
  marketplace's plugins by name, description and keywords.

### Changed
- The install panel's Close button now has the Refresh button's shape, in the Uninstall
  button's red.
- Plugin rows: the name, toggle and Uninstall sit on the top line, and the tags and the
  skills/agents/hooks lists use the full row width below it.
- Installed plugin rows are separated by a 5px gap and a full rounded border instead of a
  single hairline.

## [0.9.4] - 2026-08-30

### Fixed
- Skill and agent descriptions in the expanded plugin view now show the frontmatter text in
  full. Both frontmatter readers cut a description at its first line break: the plain-scalar
  branch matched a single line, and the VSCode extension's block-scalar (`>-`/`>`/`|`) branch
  stopped at the first line too.

## [0.9.3] - 2026-08-17

### Added
- Loading state in the VSCode panel — a spinner and skeleton rows replace the blank panel
  shown on first open while the webview loads. The markup and its styles are inlined in
  `panel.html` so they paint on the first frame, before `styles.css` and `webview/js` are
  fetched. The project card stays hidden until it has a name and path to show, so it does
  not sit next to the spinner as an empty outline.
- Content-Security-Policy on the webview (`default-src 'none'`), so script that reaches the
  panel cannot load remote code or reach the network.

### Changed
- The VSCode panel now asks for its first load with a `ready` message instead of the
  extension pushing one after setting the HTML. Pushed early, that message was dropped
  whenever the panel's scripts took longer than ~200ms to load — VSCode promotes a
  webview frame from pending to active on a 200ms fallback timer and flushes its buffered
  messages into it, so the message could land in a document that had not yet registered a
  listener. Nothing retried it, so the panel could sit on the loading skeleton forever.

### Fixed
- **Command injection on install/uninstall.** The `claude` CLI is spawned with `shell: true`,
  and Node does not quote arguments in shell mode, so a plugin id containing shell
  metacharacters — read from `marketplace.json` or `installed_plugins.json`, files this tool
  does not own — ran as a second command. Ids are now checked against the
  `name@marketplace` format before spawning.
- **Script injection in both webviews.** Plugin ids are interpolated into inline `onclick`
  handlers, a JS context nested in an HTML attribute. `esc()` does not escape single quotes,
  and HTML entities decode before the handler is parsed, so a quote in an id broke out into
  script context. A new `jsStr()` helper escapes for the JS context first.
- **Markup injection through element ids, in both webviews.** The same untrusted plugin ids
  were interpolated into `id="…"` attributes through `CSS.escape`, whose backslash escapes
  are meaningless in HTML — an id carrying a double quote closed the attribute. `CSS.escape`
  was never needed: these ids are only ever read back with `getElementById`, which matches an
  id literally rather than as a selector. Attributes are now written with `esc()` and the
  lookups use the plain id.
- **Cross-site requests to the HTTP server.** Every `POST` has a side effect — writing
  settings, running the `claude` CLI, stopping the server — and CORS stops a cross-origin
  page from reading the response, not from sending the request; a simple POST is not
  preflighted at all. Any page visited while the server ran could install a plugin or
  repoint the project root. A `POST` is now rejected with 403 unless its `Origin` matches
  the server's own origin, host and port. A missing `Origin` (curl, PowerShell, the smoke
  tests) is still allowed.
- **Smoke tests destroyed the real plugin registry.** Both suites overwrote
  `~/.claude/plugins/installed_plugins.json` with a fixture and deleted it in cleanup, with
  no backup — so running the tests on a machine with Claude Code installed wiped the
  developer's plugin registry. The real file is now stashed before the run and restored
  afterwards.
- **File-watcher leak in the VSCode extension.** `resolveWebviewView` registered four
  watchers on `context.subscriptions` every time it ran and never disposed them, so each
  panel rebuild added a set and every settings change triggered one full plugin scan per
  leaked set. Watchers are now disposed with the view.
- **The user-level file watchers never fired.** The watchers for `~/.claude/settings.json`
  and `~/.claude/plugins/installed_plugins.json` were created from absolute path strings,
  which VSCode treats as globs and matches against workspace files only — so installing a
  plugin from the CLI left an open panel stale. Both are now built with a `RelativePattern`
  rooted at the home directory.

## [0.9.2] - 2026-08-10

### Added
- **manual only** tag on skills whose `SKILL.md` front matter sets
  `disable-model-invocation: true`, on both surfaces (HTML and VSCode webview). The tag
  marks a skill the model cannot invoke; model invocation is the default, so skills
  without the key are untagged.

## [0.9.1] - 2026-06-12

First release tracked in the claude-code-command-center monorepo. Capabilities at this
version (carried over from prior development):

### Added
- Three-scope plugin model — plugins grouped into Local, Project, and User scopes, each
  backed by its own settings file, with per-scope toggle and install/uninstall.
- Two surfaces sharing one file-based data contract: a stateless HTML HTTP server
  (`html/server.py`) and a stateful VSCode extension webview.
- Marketplace install/uninstall on plugin rows, streaming progress output inline.
- `skillsToggle.confirmActions` VSCode setting (default `false`) gating the enable/disable
  and uninstall confirmation dialogs.

### Fixed
- Webview brand mark missing in packaged installs: the `__ICON_SVG__` replacement in
  `extension.js` matched the token inside an explanatory HTML comment instead of the `<h1>`
  placeholder. The comment no longer contains the token and the replace is global with a
  function replacement that guards `$`-patterns in the SVG.
