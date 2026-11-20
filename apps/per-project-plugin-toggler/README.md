# claude-code-plugin-toggler

A developer tool for managing Claude Code skill plugins. Toggle plugins on/off per-project from a VSCode sidebar. Browse and install new plugins from known marketplaces without leaving the editor.

**User guide:** [VSCode extension](docs/user-guide-vscode.md)

The earlier browser version is archived under [`archive/`](archive/). It is frozen: not built, not tested, and not kept runnable.

## How it works

Reads installed plugins from `~/.claude/plugins/installed_plugins.json` (global, managed externally) and writes enabled/disabled state to `.claude/settings.local.json` in the current project root. Claude Code picks up the updated settings on the next session.

```
~/.claude/plugins/installed_plugins.json   (global — source of installed plugins)
~/.claude/plugins/known_marketplaces.json  (global — marketplace registry)
        │
        └──▶ vscode-extension/extension.js  ←Webview→  vscode-extension/webview/panel.html
                    │
                    ▼
        <project>/.claude/settings.local.json   (per-project — enabled state)
```

The VSCode extension has no npm runtime dependencies.

> **Future work — selectable Claude config dir.** The extension currently hardcodes `~/.claude` as
> the user-scope config dir (reads and writes). If we ever need to target a different dir (multiple
> installs/profiles, or a relocated config), the low-effort, low-risk move is to honor Claude Code's
> own `CLAUDE_CONFIG_DIR` env var (fallback `~/.claude`) — writes
> then land where Claude actually reads. A free-form UI dir picker is deliberately deferred: this
> tool *writes* enablement state, so pointing it at a dir Claude isn't using is a silent footgun.

## Panel loading behaviour (VSCode)

Switching to another activity-bar container and back leaves the panel briefly empty. VSCode
disposes a hidden webview view, so returning re-runs `resolveWebviewView`: re-parse
`panel.html`, re-fetch `styles.css` and the seven `webview/js` files through the extension
host, then walk every plugin's `skills/`, `agents/`, `hooks/` and every `marketplace.json`.

What covers it today is **a loading state** (`#status` in `panel.html`): a spinner and
skeleton rows in place of a blank panel. Its markup *and* its CSS are inlined in
`panel.html` on purpose — they must paint on the webview's first frame, before `styles.css`
and `webview/js` are fetched. Do not move these rules into `webview/styles.css`; that file
arrives too late to help.

**The webview asks for its own first load.** `main.js` posts `ready` once its scripts have
run, and only then does the extension call `_refresh`. Do not "simplify" this back into a
push from `resolveWebviewView`. VSCode promotes a webview frame from pending to active on a
200ms fallback timer (`hookupOnLoadHandlers` in the webview host's `pre/index.html`) and
flushes its buffered messages into it whether or not the inner document has finished
loading. This panel routinely needs longer than that at startup, so a pushed `load` could
land in a document with no listener yet — and nothing retried it, leaving the panel on the
skeleton forever. The handshake also keeps what the earlier one-tick deferral was for: the
synchronous filesystem walk now starts strictly after the panel has painted.

> **Considered and not taken — `retainContextWhenHidden`.** Passing
> `{ webviewOptions: { retainContextWhenHidden: true } }` as the third argument to
> `registerWebviewViewProvider` keeps the hidden panel alive, so a container switch stops
> rebuilding it entirely and returning is instant. Scroll position and expanded skill lists
> would survive too. Two reasons it is not on:
>
> 1. **Memory.** VSCode documents the option as expensive: one idle webview held per window
>    for the whole session. This panel is plain DOM plus seven small classic scripts, so the
>    footprint should be modest, **but it has not been measured**.
> 2. **Freshness rests on fewer legs.** A rebuild is an unconditional re-read of every
>    source file. Retaining the panel replaces that with `onDidChangeVisibility` →
>    `_refresh`, which should be equivalent, plus the file watchers. It also removes an
>    accidental recovery path: webview JS state survives, so a stuck `operationInProgress`
>    flag can no longer be cleared by switching away and back.
>
> Revisit if the rebuild becomes the top complaint again.

**The four file watchers.** `resolveWebviewView` creates one `FileSystemWatcher` per source
file, and all four are built with `RelativePattern` — the two workspace ones
(`.claude/settings.json`, `.claude/settings.local.json`) rooted at the project folder in use
(rebuilt whenever a multi-root workspace switches folder or the folder list changes), the
two user ones (`~/.claude/settings.json`, `~/.claude/plugins/installed_plugins.json`) rooted
at the home directory. Rooting matters: a bare absolute path string is a glob, and VSCode
matches globs against workspace files only, so the user-level pair silently never fired
until they were rebuilt this way. No pattern contains `**`, so none of them watches a
directory recursively. **Not verified at runtime.** The watchers belong to the view, not to
the extension, and are disposed with it — `resolveWebviewView` runs again on every container
switch, so registering them on `context.subscriptions` leaked a set per rebuild.

Still on the list: `_refresh` re-reads every `SKILL.md` on every refresh with no caching.

## Quick start

**VSCode extension** — dev mode: open `vscode-extension/` and press `F5`. To package:

```bash
cd vscode-extension && vsce package   # produces .vsix
```

## Data format

**`~/.claude/plugins/installed_plugins.json`**
```json
{ "plugins": { "frontend-design@anthropic": {}, "docx@anthropic": {} } }
```

**`~/.claude/plugins/known_marketplaces.json`**
```json
{
  "ceh-plugins": {
    "installLocation": "C:\\Users\\user\\.claude\\plugins\\marketplaces\\ceh-plugins",
    "lastUpdated": "2026-05-14T14:18:52.841Z"
  }
}
```

**`.claude/settings.local.json`** (written by this tool)
```json
{ "enabledPlugins": { "frontend-design@anthropic": true, "docx@anthropic": false } }
```

Plugin ID format: `name@marketplace`.

Skills and agents are read from the plugin's install path at load time:

```
<installPath>/skills/<skill-dir>/SKILL.md     # YAML front matter: name, description,
                                              #   disable-model-invocation
<installPath>/agents/<agent>.md               # YAML front matter: name, description
```

A skill whose front matter sets `disable-model-invocation: true` is listed with a
**manual only** tag: the model cannot invoke it, so you must call it yourself. Model
invocation is the default, so skills without the key carry no tag.

Marketplace plugin listings are read from:

```
<installLocation>/.claude-plugin/marketplace.json
```

## Requirements

- **VSCode extension:** VSCode 1.80+
- **Install feature:** `claude` CLI on `PATH`

## Releases

Tagged `pppt-vX.Y.Z`; see [CHANGELOG.md](CHANGELOG.md) for release history and the monorepo
[release guide](../../docs/releasing.md) for how a release is cut.
