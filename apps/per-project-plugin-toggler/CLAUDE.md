# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running

See README.md for full usage. Quick agent reference:

- **VSCode extension dev:** open `vscode-extension/`, press `F5`, then click the **Plugin
  Toggler** icon in the activity bar of the new window (the extension contributes no command).
  Package with `cd vscode-extension && npm run package`, which writes
  `dist/claude-code-plugin-toggler.vsix` and copies the root `LICENSE` and the member
  `CHANGELOG.md` into the extension folder first (both copies are git-ignored).

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
  `workspaceState` under `pluginToggler.selectedProject`, falling back to the first folder). The
  host validates every `selectProject` path against the open folders.

## Key implementation details

- The extension's reader for installed plugins/skills/agents/hooks is a Node port of the in-repo
  `claude-plugins` Python library — see `docs/shared-plugin-logic.md`.
- VSCode extension confirmation is opt-in via the `pluginToggler.confirmActions` setting (default `false`). When enabled, toggle/uninstall show a `showWarningMessage`; on cancel, current state is re-posted to reset the webview toggle. When disabled (default), these actions apply immediately.
- The VSCode webview requests its own first load with a `ready` message; the extension must not
  push `load` from `resolveWebviewView` (see README — VSCode's 200ms frame-promotion timer drops it).
- The webview allows no inline script (`script-src` is the extension's own files only). Wire a
  new button with a `data-action` attribute and a row in `webview/js/events.js`, never an
  inline `onclick`.
- User-level paths go through `claudeDir()`, which honours `CLAUDE_CONFIG_DIR`.
- The `claude` CLI is looked up on `PATH` only (`resolveClaude`), never by bare name.
- No npm runtime dependencies — `@types/vscode` is dev-only.

## Tests

Unit tests with Node's built-in runner, no test dependency: `cd vscode-extension && npm test`
(`node --test test/`). CI (`.github/workflows/extension.yml`) also runs ESLint
(`npm run lint`: `extension.js`, `webview/js`, `test`, `test-support`, `scripts`) and a
packaging check (`npm run package`).

- `test/` holds only `*.test.js` files. Helpers live in `test-support/`, because Node 20 may
  run every `.js` file under a folder named `test` as a test.
- `test-support/load-extension.js` loads `extension.js` with `test-support/vscode-stub.js`
  standing in for the `vscode` module. Add what a new test needs to the stub or the loader;
  do not add a second loader.
- Any test that reaches the file system calls `useTempHome(t)` first, so it never reads or
  writes the real `~/.claude`.
- `extension.js` exports its internals for tests under `_internals`. Add a function there
  when a test needs it.
- The webview scripts under `webview/js/` need a DOM, so only what runs against a few stubbed
  globals is tested: `test/empty-state.test.js` runs `render.js` through `vm` with elements
  as plain objects. Anything else in the webview is checked by hand in a real window.
