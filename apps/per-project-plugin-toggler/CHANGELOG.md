# Changelog

All notable changes to the per-project-plugin-toggler are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are tagged `pppt-vX.Y.Z` (see [`docs/releasing.md`](../../docs/releasing.md)).
Development through 0.9.x predates this monorepo and happened in a previous repository;
this log starts at the first release tracked here.

## [Unreleased]

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
