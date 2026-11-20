# Claude Code Plugin Toggler

Enable and disable [Claude Code](https://code.claude.com/docs) plugins per project from a VS Code sidebar, and see the skills, agents and hooks each plugin brings. Install and uninstall plugins from your Claude Code marketplaces without leaving the editor.

## Requirements

- VS Code 1.144 or later
- A folder open in the window. The panel works on one project folder at a time.
- The `claude` CLI on `PATH` to install, uninstall and refresh marketplaces. Enabling and disabling plugins works without it.

## What it reads and writes

The extension runs no server and makes no network request of its own. It reads and writes the same files Claude Code uses, and Claude Code picks up a change on its next session.

| File | Read or written | Who it affects |
|------|-----------------|----------------|
| `<project>/.claude/settings.local.json` | Read. Written when you toggle a plugin in **Local plugins**. | Just you, in this project |
| `<project>/.claude/settings.json` | Read. Written when you toggle a plugin in **Project plugins**. | Everyone on the project, when the file is committed |
| `~/.claude/settings.json` | Read. Written when you toggle a plugin in **User plugins**. | All your projects |
| `~/.claude/plugins/installed_plugins.json` | Read only. Lists which plugins are installed, and at which scope. | |
| `~/.claude/plugins/known_marketplaces.json` and each marketplace's `marketplace.json` | Read only. Lists what you can install. | |
| Each installed plugin's `skills/`, `agents/` and `hooks/hooks.json` | Read only. Shown in the plugin rows. | |

- A toggle changes only the `enabledPlugins` entry of that one plugin. The rest of the settings file is kept as it is.
- A settings file that is not valid JSON is never overwritten. The panel shows the error instead.
- If you set `CLAUDE_CONFIG_DIR`, the extension uses that folder in place of `~/.claude`, as Claude Code does. Set it in the environment VS Code starts from.
- Install, uninstall and marketplace refresh are done by the `claude` CLI, run in the project folder. The extension looks for `claude` on `PATH` only.

## Opening the panel

Click the **Plugin Toggler** icon in the activity bar. The panel opens in the sidebar. The **PROJECT** card at the top shows the folder the panel works on.

## Managing plugins

Plugins are grouped by scope:

| Section | Settings file | Meaning |
|---------|---------------|---------|
| **Local plugins** | `.claude/settings.local.json` | Your own choice for this project |
| **Project plugins** | `.claude/settings.json` | Shared with the project |
| **User plugins** | `~/.claude/settings.json` | Applies to all your projects |

- **Enable or disable**: flip the toggle on a plugin row. The change is saved at once to the settings file of that section and takes effect on the next Claude Code session.
- **Enable all** and **Disable all** apply to **Local plugins** only, because the other two sections reach further than this project.
- **Uninstall** removes the plugin at that scope, with `claude plugin uninstall`. The CLI's output shows in the row while it runs.
- A row tagged **Not installed** is a plugin that a settings file names but that is not installed at that scope. Its **Install** button installs it there.

A plugin with no entry in a settings file counts as enabled.

## Viewing skills, agents and hooks

Each installed plugin row shows what the plugin brings, as counts such as **3 skills**, **1 agent** and **2 hooks**. Click a count to open the list.

- Skills and agents are listed by name and description.
- Hooks are listed by event, with the matcher and what each hook runs.
- A skill tagged **manual only** cannot be invoked by the model, so you call it yourself. Skills without the tag can be invoked either way.

## Installing from a marketplace

1. Click **+ Install/Uninstall plugin** under the plugin list.
2. Pick a marketplace from the **Marketplace** dropdown. The search box filters its plugins by name, description and keywords.
3. On a plugin row, pick the scope to install at (Local, Project or User) and click **Install**. Scopes where the plugin is already installed are marked **Installed**.
4. The CLI's output shows in the row. When it ends, the panel reloads.

**Refresh** runs `claude plugin marketplace update`, which fetches the latest plugin lists. Marketplaces themselves are added with Claude Code (`claude plugin marketplace add`), not in this panel.

The button sits under the plugin list, so it shows once the project has at least one plugin. Install your first plugin with the `claude` CLI.

## Multi-root workspaces

With two or more folders in the workspace, the **PROJECT** card becomes a dropdown of the folders. Pick one and the panel reloads for that folder: its plugins, its settings files, and the folder the `claude` CLI runs in.

- The choice is remembered per workspace.
- If the selected folder is removed from the workspace, the panel falls back to the first folder.
- The dropdown is disabled while an install or uninstall is running.

## Live updates

The panel reloads on its own when one of these files changes, for example after you run `claude plugin install` in a terminal:

- `<project>/.claude/settings.local.json`
- `<project>/.claude/settings.json`
- `~/.claude/settings.json`
- `~/.claude/plugins/installed_plugins.json`

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `pluginToggler.confirmActions` | `false` | Ask for confirmation before enabling, disabling or uninstalling a plugin. When off, these actions apply at once. Installing never asks. |

## Workspace trust

The extension is turned off in Restricted Mode and in virtual workspaces.

- In a folder you have not trusted, it stays off because it runs the `claude` CLI in that folder and writes Claude Code settings files there.
- In a virtual workspace, it stays off because it reads and writes files on the local disk.

## Troubleshooting

**"No workspace folder open."** Open a folder (`File > Open Folder`). The panel needs a project folder to work on.

**"No plugins found for this project."** No plugin is installed for this project or for your user, and no settings file names one. Install one with the `claude` CLI and the panel reloads.

**The panel shows a parse error.** One of the files it reads is not valid JSON. The message names the file. Fix the file and the panel reloads.

**"The claude CLI was not found on PATH."** Install Claude Code, or start VS Code from a shell where `claude` runs. Enabling and disabling plugins still works.

**A change is not picked up by Claude Code.** Settings take effect on the next Claude Code session. Restart the running session.

**The icon is not in the activity bar.** Right-click the activity bar and enable **Plugin Toggler**.

## License

Apache-2.0. See the [LICENSE](https://github.com/cheneeheng/claude-code-command-center/blob/main/LICENSE).
