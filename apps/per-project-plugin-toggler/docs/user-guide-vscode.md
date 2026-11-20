# User Guide: VS Code Extension

Claude Code Plugin Toggler is a sidebar panel inside VS Code. It works on one project at a time (the folder you have open, or the one you pick in a multi-root workspace) and reloads when the files it reads change. It runs no server.

## Prerequisites

- VS Code 1.144 or later
- The `claude` CLI on `PATH` to install, uninstall and refresh marketplaces. Enabling and disabling plugins works without it.

## Installation

### From a `.vsix` file

1. Download `claude-code-plugin-toggler.vsix` from a release, or build it (see [Building from source](#building-from-source)).
2. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
3. Run **Extensions: Install from VSIX...** and select the file.
4. Reload VS Code when prompted.

### Building from source

```bash
cd vscode-extension
npm ci
npm run package
```

This writes `dist/claude-code-plugin-toggler.vsix`.

### Development mode

1. Open the `vscode-extension/` folder in VS Code (not the repo root).
2. Press `F5`. A new **Extension Development Host** window opens with the extension loaded.
3. In that window, open a project folder and use the extension normally.

## Opening the panel

Click the **Plugin Toggler** icon in the activity bar. The panel opens in the sidebar.

## Choosing the project

The **PROJECT** card at the top of the panel shows the project the panel works on, with its path underneath.

| Window | PROJECT card |
|--------|--------------|
| One folder open | Shows that folder's name. It is fixed: there is nothing to choose. |
| Multi-root workspace (two or more folders) | A dropdown of the workspace's folders by name. Pick one and the panel reloads for that folder: its local and project plugins, its `.claude/` settings, and the folder the `claude` CLI runs in for install, uninstall and marketplace refresh. |

In a multi-root workspace:

- The choice is remembered per workspace, so it is still selected after you reload the window.
- If you remove the selected folder from the workspace, the panel falls back to the first folder.
- The dropdown is greyed out while an install or uninstall is running, and comes back when it ends.
- If the selected folder's settings cannot be read (for example invalid JSON in `.claude/settings.local.json`), the panel shows an error naming the folder and keeps the dropdown, so you can switch to another folder.

## Understanding the plugin list

Plugins are shown in three sections, one per scope:

| Section | Settings file | Who it affects |
|---------|---------------|----------------|
| **Local plugins** | `<project>/.claude/settings.local.json` | Just you, in this project |
| **Project plugins** | `<project>/.claude/settings.json` | Everyone on the project, when the file is committed |
| **User plugins** | `~/.claude/settings.json` | All your projects |

A section lists the plugins installed at that scope, plus any plugin its settings file names. A plugin a settings file names that is not installed at that scope is tagged **Not installed** and has an **Install** button. A plugin with no entry in a settings file counts as enabled.

If you set `CLAUDE_CONFIG_DIR`, the extension uses that folder in place of `~/.claude`, as Claude Code does.

### Enabling / disabling a plugin

Flip the toggle on a plugin row. The change is written at once to the settings file of that section, and only the plugin's `enabledPlugins` entry changes. Claude Code picks it up on the next session start.

There is no confirmation by default. To be asked first, turn on `pluginToggler.confirmActions` (see [Settings](#settings)). If you cancel, the toggle goes back to its previous state.

A settings file that is not valid JSON is never overwritten: the panel shows the error instead.

### Bulk actions

**Enable all** and **Disable all** apply to the **Local plugins** section only.

### Uninstalling a plugin

Click **Uninstall** on a plugin row. The extension runs `claude plugin uninstall` for that scope and shows the CLI's output in the row. With `pluginToggler.confirmActions` on, it asks first.

## Viewing skills, agents and hooks

Each installed plugin row shows counts such as **3 skills**, **1 agent** and **2 hooks**. Click a count to open the list: skills and agents by name and description, hooks by event with the matcher and what each hook runs.

A skill tagged **manual only** cannot be invoked by the model, so you call it yourself. Model invocation is the default, so skills without the tag can be invoked either way.

## Installing plugins from a marketplace

1. Click **+ Install/Uninstall plugin** under the plugin list.
2. Pick a marketplace from the **Marketplace** dropdown. The search box filters its plugins by name, description and keywords.
3. Each row shows name, version, the scopes where the plugin is installed, description and keywords.
4. Pick the scope to install at (Local, Project or User) and click **Install**. Installing does not ask for confirmation.
5. The CLI's output shows in the row. On success, the plugin list and the install panel reload.

**Refresh** runs `claude plugin marketplace update`. **Close** closes the install panel. Marketplaces are added with Claude Code (`claude plugin marketplace add`), not in this panel.

> If `claude` is not on `PATH`, the error appears in the plugin row at install time, not when the panel loads.

## Live updates

The panel reloads on its own when one of these files changes:

- `<project>/.claude/settings.local.json`
- `<project>/.claude/settings.json`
- `~/.claude/settings.json`
- `~/.claude/plugins/installed_plugins.json`

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `pluginToggler.confirmActions` | `false` | Ask for confirmation before enabling, disabling or uninstalling a plugin. When off, these actions apply at once. |

## Workspace trust

The extension is turned off in Restricted Mode, because it runs the `claude` CLI in the workspace folder and writes settings files there. It is also off in virtual workspaces, because it reads and writes files on the local disk.

## Troubleshooting

### "No workspace folder open."

Open a folder (`File > Open Folder`). In a multi-root workspace, check which project the PROJECT card dropdown has selected (see [Choosing the project](#choosing-the-project)).

### "No plugins found for this project."

No plugin is installed for this project or for your user, and no settings file names one. Check that `~/.claude/plugins/installed_plugins.json` exists, and install a plugin with **+ Install/Uninstall plugin** or the `claude` CLI.

### "The claude CLI was not found on PATH."

Install Claude Code, or start VS Code from a shell where `claude` runs.

### Changes not reflected in Claude Code

Settings take effect on the next Claude Code session. Restart any running session after making changes.

### Extension not visible in activity bar

Right-click the activity bar and enable **Plugin Toggler**.
