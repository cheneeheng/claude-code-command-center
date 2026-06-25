# Changelog

All notable changes to Vantage are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-15

First public release. Vantage is a local, serverless repo explorer: point it at a folder of Git
repos, survey them as cards, diff any two files across repos, and copy one onto the other.

### Added

- **Repo board.** Renders every immediate subfolder of a chosen root as a card, with detected
  stack (Node, Rust, etc.), last-activity time, and an expand chevron.
- **Folder access via the File System Access API.** Pick a projects root with **Change folder**;
  the directory handle is persisted in IndexedDB so reopening the page reconnects without
  re-picking (one permission re-grant click via **Reconnect folder**). Scan results are cached.
- **Sorting and filtering.** Order the board by last activity, name (A–Z), or stack, and filter
  cards by name.
- **Lazy file trees.** Expand a card's chevron to browse its repo file tree, built on demand.
- **Cross-repo file comparison.** Assign a file to side **A** and another from any repo to side
  **B**; both contributing cards stay highlighted with A/B badges, and the focused card is shown
  distinctly. A selection bar exposes **Swap** and **Clear**.
- **Slide-in diff sidebar.** A hand-written line-based (LCS) diff opens automatically once both
  sides are set. The sidebar is **open** or **minimized** to a floating puck — there is no close;
  the selection is preserved on minimize and only removed by **Clear**. Binary files are detected
  and skipped.
- **Copy across repos.** **Copy A → B** / **Copy B → A** overwrites the destination file behind a
  confirm step that names the exact target. This is the only destructive action; there is no
  delete. Reads and writes stay inside the chosen root.
- **Open in VSCode (optional).** Set the projects root's absolute path with **Set root path** to
  enable a per-card **Open in VSCode** button (`vscode://file/...`). Works fully without it.
- **Last-activity proxy.** Activity time is derived from file modification times
  (`.git/logs/HEAD` → `.git/HEAD` → a shallow working-tree walk), never parsed Git history.

### Architecture

- Zero dependencies, no build step, no server, no network calls. The app is a set of static
  files — `index.html` plus `styles/*.css` and `scripts/*.js` — loaded as classic
  `<link>`/`<script>` tags.
- Cross-file sharing goes through a single `window.Vantage` namespace (no ES modules, so it runs
  over `file://`); load order in `index.html` is the dependency contract.

[1.0.0]: https://github.com/cheneeheng/vantage/releases/tag/v1.0.0
