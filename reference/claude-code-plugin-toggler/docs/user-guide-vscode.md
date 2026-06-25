# User Guide — VSCode Extension

The VSCode extension embeds the plugin manager as a sidebar panel inside VSCode. It uses the first workspace folder as the project root and watches for file changes without needing a separate server process.

## Prerequisites

- VSCode 1.80 or later
- Node.js is not required separately — VSCode bundles its own runtime
- The `claude` CLI on `PATH` if you want to install plugins from the marketplace

## Installation

### From a `.vsix` file (recommended for end users)

1. Download or build the `.vsix` file (see [Building from source](#building-from-source) below).
2. Open VSCode.
3. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
4. Run **Extensions: Install from VSIX...** and select the file.
5. Reload VSCode when prompted.

### Building from source

```bash
cd vscode-extension
vsce package
```

This produces `claude-code-plugin-toggler-<version>.vsix` in the same directory. The `prepackage` script syncs the webview CSS automatically — no manual step needed.

### Development mode

1. Open the `vscode-extension/` folder in VSCode (not the repo root).
2. Press `F5`. A new **Extension Development Host** window opens with the extension loaded.
3. In that window, open a project folder and use the extension normally.

## Opening the panel

Click the **Skills Toggle** icon in the VSCode activity bar (left sidebar). The panel opens in the primary sidebar. It stays open across sessions — VSCode restores it on next launch.

## Understanding the plugin list

Plugins are shown in two sections:

| Section | What it means |
|---------|---------------|
| **Local** | Has an explicit entry in this project's `.claude/settings.local.json`. You can toggle it on or off directly. |
| **Inherited** | No local override — the plugin is treated as enabled by Claude Code. To toggle it, click **Localize** first. |

### Enabling / disabling a plugin

Flip the toggle on any **Local** plugin. VSCode shows a confirmation dialog before writing the change. If you cancel, the toggle resets to its previous state.

The change is written to `.claude/settings.local.json` in the workspace root. Claude Code picks it up on the next session start.

### Localizing an inherited plugin

1. Find the plugin in the **Inherited** section.
2. Click **Localize**. VSCode shows a confirmation dialog.
3. On confirm, the plugin moves to the **Local** section with its current state pinned.
4. Now toggle it as needed.

### Bulk actions

**Enable all** and **Disable all** apply only to plugins already in the **Local** section.

## Viewing plugin skills

Each plugin row shows a skill count badge. Click it to expand an inline list of skill names and descriptions.

## Installing plugins from a marketplace

1. Click **+ Install plugin** (right of the bulk-actions row).
2. Select a marketplace from the dropdown.
3. Browse the plugin list. Each row shows name, version, install status, description, and tags.
4. Click **Install** on an uninstalled plugin. VSCode shows a confirmation before proceeding.
5. On success, both the plugin list and the marketplace panel refresh automatically.

> If `claude` is not on `PATH` the error appears inline in the plugin row at install time, not on panel load.

## Live updates

The extension watches `.claude/settings.local.json` and `~/.claude/plugins/installed_plugins.json` using `vscode.workspace.createFileSystemWatcher`. The panel refreshes silently whenever either file changes — no manual reload needed.

## Troubleshooting

### Panel shows no plugins / blank panel

- Verify the workspace has a folder open (`File > Open Folder`). The extension uses the first workspace folder as project root; it does not work in a windowless VSCode instance.
- Check that `~/.claude/plugins/installed_plugins.json` exists. If it doesn't, the panel enters mock mode (banner shown).

### Confirmation dialog does not appear / toggle resets immediately

VSCode webview dialogs require the panel to be in the foreground. If the panel lost focus during a drag-resize, click it once to refocus before toggling.

### Changes not reflected in Claude Code

Settings take effect on the next Claude Code session. Restart any active Claude Code terminal or IDE integration after making changes.

### Extension not visible in activity bar

Open the Command Palette and run **Skills: Manage Plugins** to bring the panel into focus. If the icon is hidden, right-click the activity bar and ensure the extension is not disabled.
