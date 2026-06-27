---
artifact: ITER_03
status: ready
created: 2026-05-14
scope: Correct local/global plugin split, version numbers, agents disclosure, skill directory fix, project section rework
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture

### Component diagram
> Unchanged — see ITER_01.md §02

### Data model (updated)

**Skill** — updated from ITER_02.md §02:
- `name` — string, from `name` key in SKILL.md front matter, or folder name as fallback
- `description` — string, from `description` key in SKILL.md front matter, empty string if absent

> **Structure fix from ITER_02:** each skill is a *folder* under `<installPath>/skills/`, and agents are `.md` files under `<installPath>/agents/`. `installPath` comes from the matching entry in `installed_plugins.json` (e.g. `~/.claude/plugins/cache/ceh-plugins/ceh-dev-tools/1.1.0`), not a derived path. Example:
> ```
> ~/.claude/plugins/cache/ceh-plugins/ceh-dev-tools/1.1.0/
> ├── skills/
> │   ├── dev-tools/
> │   │   └── SKILL.md        ← read this
> │   └── another-skill/
> │       └── SKILL.md        ← read this
> └── agents/
>     ├── my-agent.md         ← one file = one agent
>     └── another-agent.md
> ```

**Agent** — new entity, nested inside `InstalledPlugin`:
- `name` — string, filename stem (e.g. `my-agent` from `my-agent.md`)
- `description` — string, from `description` key in front matter, empty string if absent

**InstalledPlugin** — revised shape, supersedes ITER_02.md §02:
- `id` — string, `pluginname@marketplace`
- `name` — string, part before `@`
- `marketplace` — string, part after `@`
- `version` — string, from `installed_plugins.json` entry (e.g. `"1.1.0"`) — **new**
- `pluginScope` — `"local"` | `"global"` — **replaces** `scope` from ITER_01/ITER_02
  - `"local"` → at least one entry in `installed_plugins.json` has `scope: "local"` and `projectPath` matching current `project_root`
  - `"global"` → at least one entry has `scope != "local"` (i.e. truly global install, no `projectPath` constraint). A plugin that is only installed locally for *other* projects does not appear in either list.
- `enabled` — boolean, from `settings.local.json`; only meaningful for `pluginScope: "local"` plugins. Global plugins are always enabled by Claude Code and this field is omitted from their response shape.
- `skills` — `Skill[]`, may be empty
- `agents` — `Agent[]`, may be empty — **new**

> **Rename note:** `scope` → `pluginScope` throughout to avoid collision with the `scope` field already present on raw entries in `installed_plugins.json`.

**`installed_plugins.json` actual shape** (confirmed from real data):
```json
{
  "ceh-dev-tools@ceh-plugins": [
    {
      "scope": "local",
      "projectPath": "C:\\Users\\Chen\\WorkLocal\\00_Project\\agent-skills",
      "installPath": "C:\\Users\\Chen\\.claude\\plugins\\cache\\ceh-plugins\\ceh-dev-tools\\1.1.0",
      "version": "1.1.0",
      "installedAt": "2026-05-14T14:56:01.642Z",
      "lastUpdated": "2026-05-14T17:28:36.777Z",
      "gitCommitSha": "0abdc82a796a3a9b82e6e65f11cd56f9987f784b"
    },
    {
      "scope": "local",
      "projectPath": "C:\\Users\\Chen\\WorkLocal\\00_Project\\claude-code-plugin-toggler",
      "installPath": "C:\\Users\\Chen\\.claude\\plugins\\cache\\ceh-plugins\\ceh-dev-tools\\1.1.0",
      "version": "1.1.0",
      "installedAt": "2026-05-14T19:25:39.642Z",
      "lastUpdated": "2026-05-14T19:25:39.642Z",
      "gitCommitSha": "0abdc82a796a3a9b82e6e65f11cd56f9987f784b"
    }
  ]
}
```

The top-level key is the plugin id. The value is an array of install entries (one per project that installed it). `load_installed_plugins()` must be rewritten to parse this structure — the old flat list format is no longer valid.

> **`installPath` as plugin directory source:** Skills and agents are read from the plugin's `installPath` directory (from the matching entry in `installed_plugins.json`), not from a derived `~/.claude/plugins/<name>/` path. This makes the PLUGINS_DIR constant from ITER_02 obsolete. Each plugin entry carries its own `installPath`.

**`GET /api/plugins` response — revised shape:**
```json
{
  "local": [
    {
      "id": "ceh-dev-tools@ceh-plugins",
      "name": "ceh-dev-tools",
      "marketplace": "ceh-plugins",
      "version": "1.1.0",
      "pluginScope": "local",
      "enabled": true,
      "skills": [
        { "name": "dev-tools", "description": "Scaffolding and code generation utilities." }
      ],
      "agents": [
        { "name": "reviewer", "description": "Reviews code for common issues." }
      ]
    }
  ],
  "global": [
    {
      "id": "frontend-design@anthropic",
      "name": "frontend-design",
      "marketplace": "anthropic",
      "version": "2.0.1",
      "pluginScope": "global",
      "skills": [
        { "name": "frontend-design", "description": "Create distinctive, production-grade frontend interfaces." }
      ],
      "agents": []
    }
  ],
  "project_root": "/path/to/project"
}
```

Global plugins omit `enabled` — they are always active and the UI renders them as read-only.

### API surface
> Unchanged from ITER_01.md §02 except `GET /api/plugins` response shape above.
> `POST /api/toggle` continues to write `settings.local.json` and is only ever called for `pluginScope: "local"` plugins.

---

## §03 · Tech Stack
> Unchanged — see ITER_01.md §03

---

## §04 · Backend

### `server.py` changes

**`load_installed_plugins(project_root)` — full rewrite**

Previous versions returned a flat list of id strings. Now returns two lists: `local_plugins` (entries matching `project_root`) and `global_plugins` (all others).

```python
def load_installed_plugins(project_root):
    """
    Returns { "local": [...], "global": [...] }
    Each entry: { "id", "version", "installPath" }

    Local  = scope=="local" and projectPath matches project_root (path-normalized).
    Global = scope!="local" OR no projectPath field.

    If a plugin id appears in both local (for this project) and global entries,
    it is placed in local only — local wins.

    If installed_plugins.json is missing, returns mock data.
    """
    installed_path = pathlib.Path.home() / ".claude" / "plugins" / "installed_plugins.json"
    if not installed_path.exists():
        return _mock_plugins()

    raw = json.loads(installed_path.read_text(encoding="utf-8"))
    # raw is { plugin_id: [ entry, ... ], ... }

    local_result = []
    global_result = []

    norm_project = str(pathlib.Path(project_root).resolve())

    for plugin_id, entries in raw.items():
        local_entry = None
        global_entry = None

        for entry in entries:
            is_local_scope = entry.get("scope") == "local"
            entry_project = entry.get("projectPath", "")
            matches_project = str(pathlib.Path(entry_project).resolve()) == norm_project if entry_project else False

            if is_local_scope and matches_project:
                local_entry = entry
                break           # prefer first matching local entry
            elif not is_local_scope and global_entry is None:
                # Truly global install (scope != "local") — always visible
                global_entry = entry
            # local-scoped entries for OTHER projects are intentionally ignored

        if local_entry:
            local_result.append({
                "id": plugin_id,
                "version": local_entry.get("version", ""),
                "installPath": local_entry.get("installPath", ""),
            })
        elif global_entry:
            # Only reachable when no local match was found for this project
            global_result.append({
                "id": plugin_id,
                "version": global_entry.get("version", ""),
                "installPath": global_entry.get("installPath", ""),
            })

    return { "local": local_result, "global": global_result }
```

**`load_plugin_skills(install_path)` — replaces ITER_02 version**

No longer derives path from plugin name. Receives `installPath` directly.

```python
def load_plugin_skills(install_path):
    """
    Reads all skill folders under <install_path>/skills/.
    Each subfolder must contain a SKILL.md at its root.
    Returns list of { "name": str, "description": str }.
    """
    if not install_path:
        return []
    skills_dir = pathlib.Path(install_path) / "skills"
    if not skills_dir.is_dir():
        return []

    skills = []
    for skill_folder in sorted(skills_dir.iterdir()):
        if not skill_folder.is_dir():
            continue
        skill_md = skill_folder / "SKILL.md"
        if not skill_md.exists():
            name, description = skill_folder.name, ""
        else:
            name, description = _parse_skill_frontmatter(skill_md)
        skills.append({"name": name, "description": description})
    return skills
```

**`load_plugin_agents(install_path)` — new**

```python
def load_plugin_agents(install_path):
    """
    Reads all .md files directly under <install_path>/agents/.
    Returns list of { "name": str, "description": str }.
    name = filename stem. description = front matter description key, or "".
    """
    if not install_path:
        return []
    agents_dir = pathlib.Path(install_path) / "agents"
    if not agents_dir.is_dir():
        return []

    agents = []
    for md_file in sorted(agents_dir.glob("*.md")):
        # _parse_skill_frontmatter already falls back to path.stem when no name key is found
        name, description = _parse_skill_frontmatter(md_file)
        agents.append({"name": name, "description": description})
    return agents
```

> `_parse_skill_frontmatter` from ITER_02 is reused unchanged for agents — the front matter format is identical.

**`merge(raw, settings)` — updated signature and logic**

```python
def merge(raw, settings):
    """
    raw = { "local": [...], "global": [...] } from load_installed_plugins()
    settings = dict from load_settings_local()
    Returns { "local": [...], "global": [...] } with full plugin dicts.
    """
    enabled_map = settings.get("enabledPlugins", {})

    def build(entry, plugin_scope):
        pid = entry["id"]
        name, marketplace = pid.split("@", 1)
        install_path = entry.get("installPath", "")
        result = {
            "id": pid,
            "name": name,
            "marketplace": marketplace,
            "version": entry.get("version", ""),
            "pluginScope": plugin_scope,
            "skills": load_plugin_skills(install_path),
            "agents": load_plugin_agents(install_path),
        }
        if plugin_scope == "local":
            result["enabled"] = enabled_map.get(pid, True)   # default: enabled
        return result

    return {
        "local":  [build(e, "local")  for e in raw["local"]],
        "global": [build(e, "global") for e in raw["global"]],
    }
```

**`RequestHandler` — `GET /api/plugins`** — see mock data section above for the full handler snippet including `mock` flag extraction.

**`POST /api/toggle`** — unchanged in behaviour. Guard added: before writing, re-read `load_installed_plugins(project_root)` and verify the requested `id` is present in the `local` list. If it is not (either it is global-only or unknown), respond `400 { "ok": false, "error": "Plugin is not installed locally for this project" }`. This prevents accidental writes for global plugins or stale/invalid ids.

**Mock data** — `_mock_plugins()` now returns the new shape:
```python
def _mock_plugins():
    return {
        "local": [
            { "id": "ceh-dev-tools@ceh-plugins", "version": "1.1.0", "installPath": "" }
        ],
        "global": [
            { "id": "frontend-design@anthropic", "version": "2.0.1", "installPath": "" }
        ],
        "mock": True
    }
```

Skills/agents will be empty for mock entries (installPath is empty string). The `"mock": True` flag must be preserved through `merge()` and included in the final HTTP response. The handler reads it from `raw` before calling `merge()` and injects it into `payload`:

```python
raw      = load_installed_plugins(self.server.project_root)
is_mock  = raw.pop("mock", False)          # extract before passing to merge
settings = load_settings_local(self.server.project_root)
merged   = merge(raw, settings)
payload  = { **merged, "project_root": self.server.project_root }
if is_mock:
    payload["mock"] = True
self._respond_json(payload)
```

---

### `extension.js` changes

**`loadInstalledPlugins(projectRoot)` — full rewrite** mirroring the Python version:

```js
function loadInstalledPlugins(projectRoot) {
  const installedPath = path.join(os.homedir(), '.claude', 'plugins', 'installed_plugins.json');
  if (!fs.existsSync(installedPath)) return _mockPlugins();

  const raw = JSON.parse(fs.readFileSync(installedPath, 'utf8'));
  const normProject = path.resolve(projectRoot);

  const local = [], global_ = [];

  for (const [pluginId, entries] of Object.entries(raw)) {
    let localEntry = null, globalEntry = null;

    for (const entry of entries) {
      const isLocal = entry.scope === 'local';
      const entryProject = entry.projectPath ? path.resolve(entry.projectPath) : null;
      const matchesProject = entryProject === normProject;

      if (isLocal && matchesProject) { localEntry = entry; break; }
      if (!isLocal && !globalEntry) globalEntry = entry;
      // local-scoped entries for OTHER projects are intentionally ignored
    }

    if (localEntry) {
      localIds.add(pluginId);
      local.push({ id: pluginId, version: localEntry.version || '', installPath: localEntry.installPath || '' });
    } else if (globalEntry) {
      global_.push({ id: pluginId, version: globalEntry.version || '', installPath: globalEntry.installPath || '' });
    }
  }

  return { local, global: global_ };
}
```

**`loadPluginSkills(installPath)` — updated** to read from `<installPath>/skills/<folder>/SKILL.md`:

```js
function loadPluginSkills(installPath) {
  if (!installPath) return [];
  const skillsDir = path.join(installPath, 'skills');
  if (!fs.existsSync(skillsDir)) return [];

  return fs.readdirSync(skillsDir)
    .filter(name => fs.statSync(path.join(skillsDir, name)).isDirectory())
    .sort()
    .map(folderName => {
      const skillMd = path.join(skillsDir, folderName, 'SKILL.md');
      if (!fs.existsSync(skillMd)) return { name: folderName, description: '' };
      const text = fs.readFileSync(skillMd, 'utf8');
      return parseSkillFrontmatter(text, folderName);
    });
}
```

**`loadPluginAgents(installPath)` — new**:

```js
function loadPluginAgents(installPath) {
  if (!installPath) return [];
  const agentsDir = path.join(installPath, 'agents');
  if (!fs.existsSync(agentsDir)) return [];

  return fs.readdirSync(agentsDir)
    .filter(f => f.endsWith('.md'))
    .sort()
    .map(f => {
      const stem = path.basename(f, '.md');
      const text = fs.readFileSync(path.join(agentsDir, f), 'utf8');
      return parseSkillFrontmatter(text, stem);
    });
}
```

**`_refresh(webview)`** — updated to call `loadPluginAgents` per plugin and include in message payload:

```js
function buildPluginList(raw, enabledMap) {
  function build(entry, pluginScope) {
    const atIdx = entry.id.indexOf('@');
    const name = atIdx === -1 ? entry.id : entry.id.slice(0, atIdx);
    const marketplace = atIdx === -1 ? '' : entry.id.slice(atIdx + 1);
    const result = {
      id: entry.id, name, marketplace,
      version: entry.version,
      pluginScope,
      skills: loadPluginSkills(entry.installPath),
      agents: loadPluginAgents(entry.installPath),
    };
    if (pluginScope === 'local') result.enabled = enabledMap[entry.id] ?? true;
    return result;
  }
  return {
    local:  raw.local.map(e  => build(e, 'local')),
    global: raw.global.map(e => build(e, 'global')),
  };
}
```

Posts `{ type: 'load', plugins: { local: [...], global: [...] }, projectRoot }` to the webview.

---

## §05 · Frontend

### Project section (replaces Header project path + picker from ITER_01)

The `Header` no longer contains the project path or change input. These move to a dedicated **Project card** rendered between the `Header` and `PluginList`.

**HTML version — Project card:**

```
┌─────────────────────────────────────────────────┐
│  Project                                        │
│  agent-skills                        [Change ▾] │
│  C:\Users\user\WorkLocal\00_Project\agent-skills│
└─────────────────────────────────────────────────┘
```

- **Project label** — small muted uppercase label `"PROJECT"`
- **Folder name** — bold, derived as the last path segment of `project_root`
- **Full path** — muted monospace, full path, wraps if long
- **Change button** — right-aligned, clicking expands an inline input area below the path:

```
┌─────────────────────────────────────────────────┐
│  Project                                        │
│  agent-skills                        [Change ▴] │
│  C:\Users\user\WorkLocal\00_Project\agent-skills│
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│  [ C:\Users\user\WorkLocal\...         ] [Apply]│
│  ✕ Path does not exist (shown on error)         │
└─────────────────────────────────────────────────┘
```

- Input is pre-filled with current path
- `[Apply]` calls `POST /api/set-project`
- On success: collapses input, updates folder name + path display, re-fetches plugins
- On error: shows error message inline below input, input stays open
- `[Change ▾]` / `[Change ▴]` arrow indicates collapsed/expanded state

**VSCode version — Project card:**

```
┌─────────────────────────────────────────────────┐
│  PROJECT                                        │
│  agent-skills                                   │
│  C:\Users\user\WorkLocal\00_Project\agent-skills│
└─────────────────────────────────────────────────┘
```

- Identical layout minus the `[Change]` button — no input, no toggle
- Path is always `projectRoot` from the `{ type: 'load' }` message
- Card is rendered but read-only

**CSS for project card** (add to both `styles.css` copies):

```css
.project-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 10px 14px;
  margin-bottom: 16px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.project-card-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}

.project-label {
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--fg-muted);
}

.project-name {
  font-size: 0.95rem;
  font-weight: 700;
  color: var(--fg);
}

.project-path {
  font-size: 0.72rem;
  font-family: monospace;
  color: var(--fg-muted);
  word-break: break-all;
}

.project-change-btn {
  background: none;
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--fg-muted);
  cursor: pointer;
  font-size: 0.72rem;
  padding: 2px 8px;
  white-space: nowrap;
}

.project-change-btn:hover {
  color: var(--fg);
  border-color: var(--accent);
}

.project-picker-expand {
  display: none;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed var(--border);
  gap: 6px;
  align-items: flex-start;
  flex-direction: column;
}

.project-picker-expand.is-open {
  display: flex;
}

.project-picker-row {
  display: flex;
  gap: 6px;
  width: 100%;
}

.project-picker-input {
  flex: 1;
  font-size: 0.8rem;
  font-family: monospace;
  padding: 4px 8px;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--fg);
}

.project-picker-error {
  font-size: 0.75rem;
  color: #cc4444;
  display: none;
}

.project-picker-error.visible {
  display: block;
}
```

---

### Component tree (updated)

```
App
├── Header                            — title + ThemeToggle (HTML only)
├── ProjectCard                       — new, replaces header project path + picker
│   ├── ProjectLabel                  "PROJECT"
│   ├── ProjectCardRow
│   │   ├── ProjectName               — folder name, bold
│   │   └── ChangeButton              — HTML only; absent in VSCode
│   ├── ProjectPath                   — full path, muted monospace
│   └── ProjectPickerExpand           — HTML only; collapses by default
│       ├── ProjectPickerInput        — pre-filled with current path
│       ├── ApplyButton
│       └── ProjectPickerError        — shown on error
├── PluginList
│   ├── Section: "Local plugins"      — only shown if local list non-empty
│   │   └── PluginRow (×N)
│   │       ├── PluginName
│   │       ├── MarketplaceBadge
│   │       ├── VersionBadge          — new: "v1.1.0", muted
│   │       ├── Toggle                — interactive
│   │       ├── SkillsDisclosure      — unchanged from ITER_02 (structure fix only)
│   │       └── AgentsDisclosure      — new, same pattern as SkillsDisclosure
│   └── Section: "Global plugins"    — only shown if global list non-empty; replaces "Inherited"
│       └── PluginRow (×N)
│           ├── PluginName
│           ├── MarketplaceBadge
│           ├── VersionBadge          — new
│           ├── GlobalBadge           — replaces InheritedBadge; label "global"
│           │                           tooltip: "Always active. Managed globally, not per-project."
│           ├── [no Toggle]           — omitted entirely
│           ├── [no OverrideButton]   — omitted entirely
│           ├── SkillsDisclosure
│           └── AgentsDisclosure      — new
└── BulkActions                       — acts on local plugins only (unchanged)
```

---

### Version badge

Displayed on every plugin row, local and global.

```html
<span class="version-badge">v1.1.0</span>
```

```css
.version-badge {
  font-size: 0.68rem;
  font-family: monospace;
  color: var(--fg-muted);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 3px;
  padding: 1px 5px;
  margin-left: 4px;
  vertical-align: middle;
}
```

If `version` is an empty string (missing from data), the badge is not rendered.

---

### Agents disclosure

Identical component pattern to `SkillsDisclosure` from ITER_02. Not rendered if `plugin.agents.length === 0`.

Disclosure toggle label: `"2 agents ▸"` / `"2 agents ▾"`.

```js
function renderAgentsDisclosure(agents) {
  if (!agents || agents.length === 0) return '';

  const agentRows = agents.map(a => `
    <div class="skill-row">
      <div class="skill-name">${escapeHtml(a.name)}</div>
      ${a.description
        ? `<div class="skill-description">${escapeHtml(a.description)}</div>`
        : ''}
    </div>
  `).join('');

  return `
    <div class="skills-disclosure">
      <button class="skills-toggle-btn" onclick="toggleSkills(this)">
        ${agents.length} agent${agents.length !== 1 ? 's' : ''} ▸
      </button>
      <div class="skills-list">
        ${agentRows}
      </div>
    </div>
  `;
}
```

> Reuses `.skills-disclosure`, `.skills-toggle-btn`, `.skills-list`, `.skill-row`, `.skill-name`, `.skill-description` CSS classes — no new CSS needed for agents.

---

### State (updated)

```js
// Posted from backend as { type: 'load', plugins: { local: [...], global: [...] }, projectRoot }
let state = {
  local: [
    {
      id: "ceh-dev-tools@ceh-plugins",
      name: "ceh-dev-tools",
      marketplace: "ceh-plugins",
      version: "1.1.0",
      pluginScope: "local",
      enabled: true,
      skills: [{ name: "dev-tools", description: "Scaffolding utilities." }],
      agents: [{ name: "reviewer", description: "Reviews code." }]
    }
  ],
  global: [
    {
      id: "frontend-design@anthropic",
      name: "frontend-design",
      marketplace: "anthropic",
      version: "2.0.1",
      pluginScope: "global",
      skills: [{ name: "frontend-design", description: "Production-grade UI." }],
      agents: []
    }
  ]
}
```

Toggle optimistic update and revert logic — unchanged, applies to local plugins only.

---

### Empty states (updated)

- Local section absent entirely if `state.local` is empty (not shown as an empty section)
- Global section absent entirely if `state.global` is empty
- If both are empty: `"No plugins found for this project. Install plugins via Claude Code."`

---

### Loading + error states
> Unchanged — see SKELETON.md §05

---

### Mock data notice

If response includes `"mock": true`, render a dismissible banner below the `ProjectCard`:

```html
<div class="mock-notice">
  ⚠ Mock data — <code>~/.claude/plugins/installed_plugins.json</code> not found.
  <button onclick="this.parentElement.remove()">✕</button>
</div>
```

```css
.mock-notice {
  font-size: 0.78rem;
  background: #fff8e1;
  border: 1px solid #ffe082;
  border-radius: 4px;
  padding: 6px 10px;
  margin-bottom: 12px;
  color: #5d4037;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme]) .mock-notice,
  :root[data-theme="dark"] .mock-notice {
    background: #3a2e00;
    border-color: #7a6200;
    color: #ffe082;
  }
}

:root[data-context="vscode"] .mock-notice {
  background: var(--vscode-inputValidation-warningBackground, #3a2e00);
  border-color: var(--vscode-inputValidation-warningBorder, #7a6200);
  color: var(--vscode-editor-foreground);
}
```

---

## Deferred

- **`styles.css` sync** — still manual between `html/` and `vscode-extension/webview/`. Makefile or symlink deferred again; becoming more urgent as CSS grows.
- **File watching** — `settings.local.json` and `installed_plugins.json` watching deferred, same as ITER_01/ITER_02.
- **Animated expand/collapse** — `max-height` transition for skill/agent lists, deferred from ITER_02.
- **Bulk actions for global plugins** — global plugins are read-only; bulk actions continue to act on local only. If a "promote all to local" action is ever wanted, defer to a future iteration.
- **Plugin description** — top-level plugin description (not skill/agent description) is not present in `installed_plugins.json`. Deferred until a plugin manifest format is defined.
- **Windows path normalisation edge cases** — `path.resolve()` / `pathlib.Path.resolve()` handles most cases, but UNC paths and drive-letter case differences on Windows are not explicitly tested. Flag for QA.
- **`.vsix` packaging** — unchanged from prior deferred list.