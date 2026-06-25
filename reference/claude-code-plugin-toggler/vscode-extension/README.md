# Skills Toggle

Manage Claude Code skill plugins per project from a VSCode sidebar. Toggle plugins on/off, browse installed skills and agents, and install new plugins from known marketplaces — without leaving the editor.

## Requirements

- VSCode 1.80 or later
- The `claude` CLI on `PATH` if you want to install plugins from a marketplace

## How it works

The extension reads installed plugins from `~/.claude/plugins/installed_plugins.json` (managed by the Claude Code CLI) and writes per-project enabled/disabled state to `.claude/settings.local.json` in your workspace root. Claude Code picks up the changes on the next session.

```
~/.claude/plugins/installed_plugins.json   ← source of installed plugins (global)
~/.claude/plugins/known_marketplaces.json  ← marketplace registry (global)
        │
        └──▶ VSCode extension
                    │
                    ▼
        <project>/.claude/settings.local.json   ← enabled state (per-project)
```

### Data formats

**Installed plugins** (`~/.claude/plugins/installed_plugins.json`):
```json
{ "plugins": { "frontend-design@anthropic": {}, "docx@anthropic": {} } }
```

**Per-project settings** (`.claude/settings.local.json`, written by this extension):
```json
{ "enabledPlugins": { "frontend-design@anthropic": true, "docx@anthropic": false } }
```

Plugin IDs use the format `name@marketplace`. Skills and agents are read from each plugin's install path:

```
<installPath>/skills/<skill-dir>/SKILL.md   # YAML front matter: name, description
<installPath>/agents/<agent>.md             # YAML front matter: name, description
```

## Opening the panel

Click the **Skills Toggle** icon in the VSCode activity bar (left sidebar). The panel opens in the primary sidebar and is restored on next launch.

## Managing plugins

Plugins appear in two sections:

| Section | Meaning |
|---------|---------|
| **Local** | Has an explicit entry in `.claude/settings.local.json`. Toggle on/off directly. |
| **Inherited** | No local override — treated as enabled by Claude Code. Click **Localize** first to pin it before toggling. |

**Enabling / disabling** — flip the toggle on any Local plugin. The change applies immediately and takes effect on the next Claude Code session. To require a confirmation dialog first, enable `Skills Toggle: Confirm Actions` in settings (see [Settings](#settings)).

**Localizing an inherited plugin** — click **Localize** in the Inherited section. On confirm, the plugin moves to Local with its current state pinned.

**Bulk actions** — **Enable all** and **Disable all** apply only to plugins in the Local section.

## Viewing skills and agents

Each plugin row shows a skill count badge. Click it to expand an inline list of skill names and descriptions.

## Installing from a marketplace

1. Click **+ Install plugin** (right of the bulk-actions row).
2. Select a marketplace from the dropdown.
3. Browse the list — each row shows name, version, install status, description, and tags.
4. Click **Install**. The panel refreshes automatically on success.

> If `claude` is not on `PATH`, the error appears inline in the plugin row at install time.

## Live updates

The extension watches `.claude/settings.local.json` and `~/.claude/plugins/installed_plugins.json`. The panel refreshes automatically when either file changes.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `skillsToggle.confirmActions` | `false` | Ask for confirmation before enabling/disabling or uninstalling a plugin. When off, these actions apply immediately. |

## Troubleshooting

**Panel shows no plugins / blank panel** — ensure a folder is open (`File > Open Folder`). The extension uses the first workspace folder as project root. If `~/.claude/plugins/installed_plugins.json` is missing, the panel shows mock data with a banner.

**Changes not reflected in Claude Code** — settings take effect on the next Claude Code session. Restart any active Claude Code terminal after making changes.

**Extension not visible in activity bar** — run **Skills: Manage Plugins** from the Command Palette. If the icon is hidden, right-click the activity bar and enable the extension.

## License

MIT
