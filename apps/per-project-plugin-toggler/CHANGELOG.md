# Changelog

All notable changes to the per-project-plugin-toggler are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are tagged `pppt-vX.Y.Z` (see [`docs/releasing.md`](../../docs/releasing.md)).
Development through 0.9.x predates this monorepo and happened in a previous repository;
this log starts at the first release tracked here.

## [Unreleased]

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
