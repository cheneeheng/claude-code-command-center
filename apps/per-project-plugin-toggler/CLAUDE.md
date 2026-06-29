# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running

See README.md for full usage. Quick agent reference:

- **HTML version** must run from the target project root (`project_root = os.getcwd()` at startup):
  `python3 html/server.py` (default port 7779; pass a port to override). Convenience launchers:
  `html/start.sh`, `html/start.ps1`, `html/start.bat`.
- **VSCode extension dev:** `F5` in VSCode → command palette → `Skills: Manage Plugins`. Package
  with `cd vscode-extension && vsce package` (the `prepackage` hook auto-runs CSS sync).

**CSS/icon sync (load-bearing) —** `html/styles.css` and `html/icon.svg` are canonical. After any
edit to either, run `make sync-css` (or `powershell scripts/sync-css.ps1`). Do not edit
`vscode-extension/webview/styles.css` or `vscode-extension/webview/icon.svg` directly — they are
overwritten by this command. (`vscode-extension/icon.svg` at the extension root is separate: the
monochrome activity-bar icon referenced by `package.json`.)

## Architecture

Two independent surfaces with shared file-based data contract — see README.md for the diagram. Key distinction:

- **HTML version:** stateless HTTP server; `project_root` is fixed at process start via `cwd`.
- **VSCode extension:** stateful webview panel; `projectRoot = vscode.workspace.workspaceFolders[0].uri.fsPath`.

Both surfaces use the same read/merge/write logic (implemented independently in Python and Node.js).

## Key implementation details

- `server.py` depends only on the in-repo `claude-plugins` library (stdlib otherwise) for
  reading installed plugins/skills/agents/hooks; no third-party pip dependencies. The VSCode
  extension ships a parallel Node port of that logic — see `docs/shared-plugin-logic.md`.
- If `installed_plugins.json` is missing, `server.py` falls back to `MOCK_PLUGINS` and sets `"mock": true` in the API response.
- VSCode extension confirmation is opt-in via the `skillsToggle.confirmActions` setting (default `false`). When enabled, toggle/uninstall show a `showWarningMessage`; on cancel, current state is re-posted to reset the webview toggle. When disabled (default), these actions apply immediately.
- CORS in `server.py` is restricted to `http://localhost` only.
- No npm runtime dependencies — `@types/vscode` is dev-only.

## No test runner configured

No test framework is set up. Tests should be added before shipping.
