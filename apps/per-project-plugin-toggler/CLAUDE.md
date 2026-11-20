# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running

See README.md for full usage. Quick agent reference:

- **VSCode extension dev:** `F5` in VSCode → command palette → `Skills: Manage Plugins`. Package
  with `cd vscode-extension && vsce package`.

**CSS/icon —** `vscode-extension/webview/styles.css` and `vscode-extension/webview/icon.svg` are
the source and are edited directly. (`vscode-extension/icon.svg` at the extension root is
separate: the monochrome activity-bar icon referenced by `package.json`.)

**Archive —** `archive/` holds the earlier browser version (HTML page, Python server, its smoke
tests and the CSS sync scripts). It is frozen: not built, not tested, not kept runnable. Do not
edit it and do not import from it.

## Architecture

One surface, the VSCode extension, over a file-based data contract — see README.md for the
diagram.

- **VSCode extension:** stateful webview panel; `projectRoot` is the single workspace folder, or
  in a multi-root workspace the folder picked in the PROJECT card dropdown (kept in
  `workspaceState` under `skillsToggle.selectedProject`, falling back to the first folder). The
  host validates every `selectProject` path against the open folders.

## Key implementation details

- The extension's reader for installed plugins/skills/agents/hooks is a Node port of the in-repo
  `claude-plugins` Python library — see `docs/shared-plugin-logic.md`.
- VSCode extension confirmation is opt-in via the `skillsToggle.confirmActions` setting (default `false`). When enabled, toggle/uninstall show a `showWarningMessage`; on cancel, current state is re-posted to reset the webview toggle. When disabled (default), these actions apply immediately.
- The VSCode webview requests its own first load with a `ready` message; the extension must not
  push `load` from `resolveWebviewView` (see README — VSCode's 200ms frame-promotion timer drops it).
- No npm runtime dependencies — `@types/vscode` is dev-only.

## Tests

No test suite. CI (`.github/workflows/extension.yml`) runs ESLint on `extension.js` and a
`vsce package` check. The Node surface has no test runner.
