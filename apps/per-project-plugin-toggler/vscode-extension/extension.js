const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

// Claude Code's user config folder. CLAUDE_CONFIG_DIR moves every ~/.claude path, the
// user settings and the plugin registry included, so reads and writes follow it.
function claudeDir() {
  return process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude");
}

function confirmActionsEnabled() {
  return vscode.workspace
    .getConfiguration("pluginToggler")
    .get("confirmActions", false);
}

function normalisePath(p) {
  if (!p) return "";
  try {
    const resolved = path.resolve(p);
    // Windows and macOS fold case in paths, so "C:\Repo" and "c:\repo" are one folder.
    // Linux does not. UNC paths (\\server\share\...) are handled by the platform resolver.
    // less-code: by platform, not by volume; a case-sensitive macOS volume would need a
    // per-path check.
    if (process.platform === "win32" || process.platform === "darwin") {
      return resolved.toLowerCase();
    }
    return resolved;
  } catch {
    return p;
  }
}

// Cross-reference: loadInstalledPlugins, parseSkillFrontmatter and the skill
// enumeration here are a parallel Node port of the libs/claude-plugins library
// (consumed by apps/claude-component-browser/server.py). A Python library
// can't serve this surface, so this copy is kept in sync by hand — see
// docs/shared-plugin-logic.md.
function loadInstalledPlugins(projectRoot) {
  const installedPath = path.join(claudeDir(), "plugins", "installed_plugins.json");
  const buckets = { local: [], project: [], user: [] };
  // No registry yet means no plugins: the panel shows its empty state.
  if (!fs.existsSync(installedPath)) return buckets;

  try {
    const raw = JSON.parse(fs.readFileSync(installedPath, "utf8"))["plugins"];
    const normProject = normalisePath(projectRoot);

    for (const [pluginId, entries] of Object.entries(raw)) {
      for (const entry of entries) {
        const scope = entry.scope;
        if (!(scope in buckets)) continue;
        if (scope === "local" || scope === "project") {
          const entryProject = entry.projectPath ? normalisePath(entry.projectPath) : null;
          if (entryProject !== normProject) continue; // belongs to a different project
        }
        buckets[scope].push({
          id: pluginId,
          version: entry.version || "",
          installPath: entry.installPath || "",
          scope,
        });
      }
    }

    return buckets;
  } catch (e) {
    throw new Error(`Failed to parse installed_plugins.json: ${e.message}`);
  }
}

// The settings file of a scope: local and project live in the project, user in the home dir.
function settingsPath(scope, projectRoot) {
  if (scope === "user") return path.join(claudeDir(), "settings.json");
  return path.join(
    projectRoot,
    ".claude",
    scope === "local" ? "settings.local.json" : "settings.json"
  );
}

// A missing file is empty settings. A file that does not parse, or whose root is not an
// object, throws: returning {} for it made the next save replace the whole file with only
// enabledPlugins.
function loadSettings(scope, projectRoot) {
  const p = settingsPath(scope, projectRoot);
  if (!fs.existsSync(p)) return {};
  let data;
  try {
    data = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    throw new Error(`Failed to parse ${p}: ${e.message}`);
  }
  if (data === null || typeof data !== "object" || Array.isArray(data))
    throw new Error(`Failed to parse ${p}: the root is not a JSON object`);
  return data;
}

// Written to a temp file beside the target and renamed over it, so a write that fails
// midway (full disk, crash) leaves the old settings intact instead of a truncated file.
function saveSettings(scope, projectRoot, settings) {
  const p = settingsPath(scope, projectRoot);
  const tmp = `${p}.${process.pid}.tmp`;
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(tmp, JSON.stringify(settings, null, 2));
    fs.renameSync(tmp, p);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw new Error(`Could not save ${p}: ${e.message}`);
  }
}

function parseSkillFrontmatter(text, fallbackName) {
  // The patterns below match "\n". A file checked out with CRLF endings (git on Windows)
  // otherwise shows a block-scalar description as just its marker, ">-".
  text = text.replace(/\r\n/g, "\n");
  const fmMatch = text.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!fmMatch)
    return { name: fallbackName, description: "", manualOnly: false };
  const fm = fmMatch[1];

  const nameMatch = fm.match(/^name:\s*(.+)$/m);
  const name = nameMatch ? nameMatch[1].trim() : fallbackName;

  // Take every indented line of the block, not just the first: a lazy match with
  // a `$` lookahead stopped at the first line break and cut the description.
  const descBlockMatch = fm.match(
    /^description:[ \t]*(?:>-|>|[|][-]?)?[ \t]*\n((?:[ \t]+\S.*\n?)*)/m
  );
  let description = "";
  if (descBlockMatch) {
    description = descBlockMatch[1]
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .join(" ");
  } else {
    // A plain (unmarked) scalar may still wrap onto more-indented lines; take
    // them all, or a long description shows up cut at its first line break.
    const descInlineMatch = fm.match(/^description:\s*(.+(?:\n[ \t]+\S.*)*)$/m);
    if (descInlineMatch)
      description = descInlineMatch[1]
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean)
        .join(" ");
  }

  // Model invocation is the default; `disable-model-invocation: true` opts out.
  const manualOnlyMatch = fm.match(/^disable-model-invocation:\s*(.+)$/m);
  const manualOnly =
    !!manualOnlyMatch && /^(["']?)true\1$/i.test(manualOnlyMatch[1].trim());

  return { name, description, manualOnly };
}

function loadPluginSkills(installPath) {
  if (!installPath) return [];
  const skillsDir = path.join(installPath, "skills");
  if (!fs.existsSync(skillsDir)) return [];

  const skills = [];
  for (const folderName of fs.readdirSync(skillsDir).sort()) {
    try {
      const text = fs.readFileSync(path.join(skillsDir, folderName, "SKILL.md"), "utf8");
      skills.push(parseSkillFrontmatter(text, folderName));
    } catch {
      // Not a skill folder, or one that cannot be read (a broken link, a locked file).
      // Skipped, so one bad entry does not put the whole panel in its error state.
    }
  }
  return skills;
}

function loadPluginAgents(installPath) {
  if (!installPath) return [];
  const agentsDir = path.join(installPath, "agents");
  if (!fs.existsSync(agentsDir)) return [];

  const agents = [];
  for (const f of fs.readdirSync(agentsDir).filter((f) => f.endsWith(".md")).sort()) {
    try {
      const text = fs.readFileSync(path.join(agentsDir, f), "utf8");
      agents.push(parseSkillFrontmatter(text, path.basename(f, ".md")));
    } catch {
      // Unreadable agent file: skipped, as an unreadable skill is.
    }
  }
  return agents;
}

function _hookDetail(h) {
  // 'command' is the common case (and the documented example); render its command string.
  if (h.type === "command") return h.command || "";
  // http / mcp_tool / prompt / agent: field names vary — show a compact dump of the
  // non-type fields rather than inventing key names. Refine when real examples appear.
  const rest = {};
  for (const [k, v] of Object.entries(h)) if (k !== "type") rest[k] = v;
  return JSON.stringify(rest);
}

function loadPluginHooks(installPath) {
  if (!installPath) return [];
  const p = path.join(installPath, "hooks", "hooks.json");
  if (!fs.existsSync(p)) return [];
  let data;
  try {
    data = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return [];
  }
  const result = [];
  for (const [event, groups] of Object.entries(data.hooks || {})) {
    for (const group of groups || []) {
      const actions = (group.hooks || []).map((h) => ({
        type: h.type || "",
        detail: _hookDetail(h),
      }));
      result.push({ event, matcher: group.matcher || "", actions });
    }
  }
  return result;
}

function buildSections(raw, settings) {
  // raw      = { local, project, user } from loadInstalledPlugins
  // settings = { local: enabledPlugins, project: enabledPlugins, user: enabledPlugins }
  function section(scope) {
    const installedEntries = {};
    for (const e of raw[scope]) installedEntries[e.id] = e;
    const enabledMap = settings[scope];
    const ids = new Set([...Object.keys(installedEntries), ...Object.keys(enabledMap)]);
    return [...ids].sort().map((pid) => {
      const atIdx = pid.indexOf("@");
      const name = atIdx === -1 ? pid : pid.slice(0, atIdx);
      const marketplace = atIdx === -1 ? "" : pid.slice(atIdx + 1);
      const entry = installedEntries[pid];
      const installed = entry !== undefined;
      const installPath = installed ? entry.installPath || "" : "";
      return {
        id: pid,
        name,
        marketplace,
        version: installed ? entry.version || "" : "",
        scope,
        enabled: enabledMap[pid] ?? true,
        installed,
        skills: installed ? loadPluginSkills(installPath) : [],
        agents: installed ? loadPluginAgents(installPath) : [],
        hooks: installed ? loadPluginHooks(installPath) : [],
      };
    });
  }
  return {
    local: section("local"),
    project: section("project"),
    user: section("user"),
  };
}

function loadKnownMarketplaces() {
  const mp = path.join(claudeDir(), "plugins", "known_marketplaces.json");
  if (!fs.existsSync(mp)) return [];
  try {
    const raw = JSON.parse(fs.readFileSync(mp, "utf8"));
    return Object.entries(raw).map(([key, info]) => ({
      key,
      installLocation: info.installLocation || "",
      lastUpdated: info.lastUpdated || "",
    }));
  } catch {
    return [];
  }
}

function loadMarketplacePlugins(marketplaceKey, installLocation) {
  if (!installLocation)
    return { plugins: [], error: "installLocation is empty" };
  const mpJson = path.join(
    installLocation,
    ".claude-plugin",
    "marketplace.json"
  );
  if (!fs.existsSync(mpJson))
    return { plugins: [], error: `marketplace.json not found at ${mpJson}` };
  try {
    const raw = JSON.parse(fs.readFileSync(mpJson, "utf8"));
    const plugins = (raw.plugins || []).map((p) => ({
      name: p.name || "",
      description: p.description || "",
      version: p.version || "",
      author: (p.author || {}).name || "",
      keywords: p.keywords || [],
    }));
    return { plugins, error: null };
  } catch (e) {
    return {
      plugins: [],
      error: `Failed to parse marketplace.json: ${e.message}`,
    };
  }
}


// Plugin ids come from marketplace.json / installed_plugins.json — files this tool does
// not own — and reach the `claude` command line, through a shell when the CLI is a .cmd
// shim. An id carrying `&`, `|` or a quote would run as a second shell command, and one
// starting with `-` would read as a CLI option. Ids are `name@marketplace`, each part
// starting with a letter or digit; anything else is rejected before spawning.
const PLUGIN_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$/;

// The `claude` executable, looked up on PATH only. Spawning the bare name through a
// shell let cmd.exe search the working directory first, which is the project folder: a
// cloned repo holding a claude.cmd would have run in place of the CLI.
function resolveClaude() {
  const windows = process.platform === "win32";
  const exts = windows
    ? (process.env.PATHEXT || ".COM;.EXE;.BAT;.CMD").split(";").filter(Boolean)
    : [""];
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    if (!path.isAbsolute(dir)) continue; // "" and "." would mean the working directory
    for (const ext of exts) {
      const candidate = path.join(dir, "claude" + ext);
      try {
        if (!fs.statSync(candidate).isFile()) continue;
        if (!windows) fs.accessSync(candidate, fs.constants.X_OK);
        return candidate;
      } catch {
        // not in this folder
      }
    }
  }
  return null;
}

// Runs `claude <args>` in cwd and passes its output to onLine as it arrives. onSpawn
// receives the child process, so the caller can stop it.
function runClaude(args, cwd, onLine, onSpawn = () => {}) {
  return new Promise((resolve, reject) => {
    const exe = resolveClaude();
    if (!exe) {
      reject(new Error("The claude CLI was not found on PATH. Install Claude Code, then try again."));
      return;
    }
    // A .cmd or .bat shim (an npm install of the CLI on Windows) only runs through the
    // shell, where Node joins the arguments unquoted: the callers validate every one.
    const viaShell = /\.(cmd|bat)$/i.test(exe);
    const proc = spawn(viaShell ? `"${exe}"` : exe, args, {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
      shell: viaShell,
    });
    onSpawn(proc);

    for (const stream of [proc.stdout, proc.stderr]) {
      let buf = "";
      stream.on("data", (chunk) => {
        buf += chunk.toString("utf8");
        const lines = buf.split("\n");
        buf = lines.pop();
        lines.forEach((l) => onLine(l + "\n"));
      });
      stream.on("end", () => {
        if (buf) onLine(buf);
      });
    }

    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(code === null ? "Stopped" : `Exit code ${code}`));
    });
    proc.on("error", reject);
  });
}

// Stops a child and what it started. On Windows the child may be a shell whose own child
// is the CLI, and killing the shell alone would leave the CLI running.
function killTree(proc) {
  if (process.platform !== "win32") {
    proc.kill();
    return;
  }
  const taskkill = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "taskkill.exe");
  spawn(taskkill, ["/pid", String(proc.pid), "/T", "/F"], { stdio: "ignore" });
}

const SELECTED_PROJECT_KEY = "pluginToggler.selectedProject";

// VSCode returns lowercase drive letters on Windows; normalize to uppercase so spawn's cwd
// matches what the CLI writes to installed_plugins.json, and so stored selections compare
// equal to the folder list.
function folderPath(folder) {
  const p = folder.uri.fsPath;
  if (/^[a-z]:/.test(p)) return p[0].toUpperCase() + p.slice(1);
  return p;
}

class SkillsViewProvider {
  static viewType = "pluginToggler.pluginList";

  constructor(extensionUri, workspaceState) {
    this._extensionUri = extensionUri;
    // The folder chosen in a multi-root workspace. workspaceState is per workspace, so the
    // choice survives a window reload without leaking into other workspaces. Only consulted
    // when two or more folders are open; a single-folder window is always fixed.
    this._workspaceState = workspaceState;
    this._selectedRoot = workspaceState.get(SELECTED_PROJECT_KEY) || null;
    // The settings watchers of the folder in use; rebuilt by _watchFolder on every switch.
    this._folderWatchers = [];
    // The `claude` calls still running, so closing the panel can stop them.
    this._running = new Set();
  }

  _claude(args, projectRoot, onLine) {
    return runClaude(args, projectRoot, onLine, (proc) => {
      this._running.add(proc);
      proc.on("close", () => this._running.delete(proc));
    });
  }

  resolveWebviewView(webviewView) {
    const stylesUri = webviewView.webview.asWebviewUri(
      vscode.Uri.joinPath(this._extensionUri, "webview", "styles.css")
    );
    const jsBaseUri = webviewView.webview.asWebviewUri(
      vscode.Uri.joinPath(this._extensionUri, "webview", "js")
    );
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.joinPath(this._extensionUri, "webview")],
    };
    webviewView.webview.html = this._getHtml(webviewView.webview, stylesUri, jsBaseUri);
    // No first refresh is posted from here. The webview asks for it with a `ready`
    // message once its scripts have run — see _onMessage. Pushing it on a timer (or
    // synchronously with the html) dropped it whenever the panel's scripts took longer
    // than ~200ms to load: VSCode's webview host promotes the frame from pending to
    // active on a 200ms fallback timer and flushes its buffered messages into it, so a
    // `load` arriving in that window hits a document that has not yet registered its
    // message listener. Nothing retried it, and the panel sat on the skeleton forever.
    webviewView.webview.onDidReceiveMessage((msg) =>
      this._onMessage(webviewView.webview, msg)
    );
    webviewView.onDidChangeVisibility(() => {
      if (webviewView.visible) this._refresh(webviewView.webview);
    });

    // File watchers — auto-refresh on settings or installed_plugins change.
    // They belong to this view, not to the extension: resolveWebviewView runs again every
    // time the view is rebuilt, so pushing them onto context.subscriptions accumulated a
    // fresh set on each rebuild that nothing disposed until deactivate — and every
    // settings change then triggered one full plugin scan per leaked set.
    // User settings + install registry — outside the workspace, so they need a
    // RelativePattern rooted at the home directory. A bare absolute path string is a
    // glob, and VSCode matches globs against workspace files only: built that way these
    // two never fired, so a CLI `claude plugin install` left an open panel stale.
    // Neither pattern contains `**`, so neither watches the home directory recursively.
    // Created whatever the folder count, so a window that gains its first folder later
    // still watches them.
    const webview = webviewView.webview;
    const home = vscode.Uri.file(claudeDir());
    const homeWatchers = [
      vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(home, "settings.json")
      ),
      vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(home, "plugins/installed_plugins.json")
      ),
    ];
    for (const w of homeWatchers) this._onFileEvents(w, webview);
    this._watchFolder(webview);

    // Folders added or removed while the panel is open: the dropdown, the fixed/selectable
    // card and the watched folder all follow. A selection whose folder is gone falls back to
    // the first folder in _projectRoot, and applies again if the folder comes back.
    const foldersListener = vscode.workspace.onDidChangeWorkspaceFolders(() => {
      this._watchFolder(webview);
      this._refresh(webview);
    });

    webviewView.onDidDispose(() => {
      for (const w of homeWatchers) w.dispose();
      for (const w of this._folderWatchers) w.dispose();
      this._folderWatchers = [];
      foldersListener.dispose();
      // Nobody is left to read their output, and a hung call would otherwise run on.
      for (const proc of this._running) killTree(proc);
    });
  }

  _onFileEvents(watcher, webview) {
    const onchange = () => this._refresh(webview);
    watcher.onDidChange(onchange);
    watcher.onDidCreate(onchange);
    watcher.onDidDelete(onchange);
  }

  // Local + project settings of the folder in use. Disposes the previous folder's pair, so
  // only the selected folder's edits refresh the panel.
  _watchFolder(webview) {
    for (const w of this._folderWatchers) w.dispose();
    this._folderWatchers = [];
    const folder = this._projectFolder();
    if (!folder) return;
    for (const rel of [".claude/settings.local.json", ".claude/settings.json"]) {
      const w = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(folder, rel));
      this._onFileEvents(w, webview);
      this._folderWatchers.push(w);
    }
  }

  // The workspace folder in use: none → null; one → that folder, whatever is stored;
  // two or more → the stored selection when it is still open, else the first folder.
  _projectFolder() {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || folders.length === 0) return null;
    if (folders.length === 1) return folders[0];
    return folders.find((f) => folderPath(f) === this._selectedRoot) || folders[0];
  }

  _projectRoot() {
    const folder = this._projectFolder();
    return folder ? folderPath(folder) : null;
  }

  // Folders offered in the dropdown: only in a multi-root workspace, so an empty list tells
  // the webview to show the fixed card.
  _projects() {
    const folders = vscode.workspace.workspaceFolders || [];
    if (folders.length < 2) return [];
    return folders.map((f) => ({ name: f.name, path: folderPath(f) }));
  }

  _refresh(webview) {
    const projectRoot = this._projectRoot();
    if (!projectRoot) {
      webview.postMessage({ type: "error", message: "No workspace folder open.", projects: [] });
      return;
    }
    // Computed before the try, so an error in the selected folder still carries the
    // folder list: the webview keeps the dropdown up and the user can switch back.
    const projects = this._projects();
    const projectName = this._projectFolder().name;
    try {
      const raw = loadInstalledPlugins(projectRoot);

      const settings = {
        local: loadSettings("local", projectRoot).enabledPlugins || {},
        project: loadSettings("project", projectRoot).enabledPlugins || {},
        user: loadSettings("user", projectRoot).enabledPlugins || {},
      };
      const sections = buildSections(
        { local: raw.local || [], project: raw.project || [], user: raw.user || [] },
        settings
      );

      // Per-id installed-scopes map for the marketplace panel (ITER_17)
      const installedScopes = {};
      for (const scope of ["local", "project", "user"]) {
        for (const p of sections[scope]) {
          if (p.installed) (installedScopes[p.id] = installedScopes[p.id] || []).push(scope);
        }
      }

      const marketplacesMeta = loadKnownMarketplaces();
      const marketplaces = marketplacesMeta.map((m) => {
        const { plugins: mpPlugins, error } = loadMarketplacePlugins(
          m.key,
          m.installLocation
        );
        const entry = { key: m.key, lastUpdated: m.lastUpdated };
        if (error) {
          entry.plugins = [];
          entry.error = error;
        } else {
          entry.plugins = mpPlugins.map((p) => ({
            ...p,
            marketplace: m.key,
            id: `${p.name}@${m.key}`,
          }));
        }
        return entry;
      });

      webview.postMessage({
        type: "load",
        plugins: sections,
        installedScopes,
        marketplaces,
        projectRoot,
        projects,
      });
    } catch (e) {
      webview.postMessage({
        type: "error",
        message: `${projectName}: ${e.message}`,
        projects,
        projectRoot,
      });
    }
  }

  async _selectProject(webview, requested) {
    const folders = vscode.workspace.workspaceFolders || [];
    // Act only on a path that is one of the open folders; anything else re-posts the
    // current state so the dropdown snaps back.
    const match = folders.find((f) => folderPath(f) === requested);
    if (!match) {
      this._refresh(webview);
      return;
    }
    // Switch and refresh before persisting, so the new folder is in use before any later
    // message is handled.
    this._selectedRoot = folderPath(match);
    this._watchFolder(webview);
    this._refresh(webview);
    await this._workspaceState.update(SELECTED_PROJECT_KEY, this._selectedRoot);
  }

  async _onMessage(webview, msg) {
    if (msg.type === "ready") {
      // The webview drives the first load: it only asks once its message listener is
      // installed, so the reply cannot be delivered into a document that would ignore it.
      this._refresh(webview);
      return;
    }
    if (msg.type === "selectProject") {
      await this._selectProject(webview, msg.path);
      return;
    }
    if (msg.type === "toggle") {
      const { id, enabled, scope } = msg;
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;
      if (!["local", "project", "user"].includes(scope)) return;
      // The webview is the only sender, but what it sends is written to a settings file.
      if (typeof id !== "string" || !id || typeof enabled !== "boolean") return;

      // Confirmation — wording escalates with blast radius. Skipped unless opted in.
      if (confirmActionsEnabled()) {
        const where =
          scope === "project"
            ? "the shared .claude/settings.json (committed, affects your team)"
            : scope === "user"
            ? "your user settings (~/.claude/settings.json, affects all your projects)"
            : ".claude/settings.local.json (just you, this project)";
        const ok = await vscode.window.showWarningMessage(
          `Set "${id}" to ${enabled ? "enabled" : "disabled"} in ${where}?`,
          { modal: scope !== "local" },
          "Confirm"
        );
        if (ok !== "Confirm") {
          this._refresh(webview); // reset the toggle's visual state
          return;
        }
      }

      // A malformed settings file or a failed save throws here, before anything is
      // written. The user is told why, and the refresh below resets the toggle (or posts
      // the error state for a file that does not parse).
      try {
        const settings = loadSettings(scope, projectRoot);
        if (!settings.enabledPlugins) settings.enabledPlugins = {};
        settings.enabledPlugins[id] = enabled;
        saveSettings(scope, projectRoot, settings);
      } catch (e) {
        vscode.window.showErrorMessage(e.message);
      }

      this._refresh(webview);
    } else if (msg.type === "marketplaceRefresh") {
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;

      webview.postMessage({ type: "marketplaceRefreshStart" });
      try {
        await this._claude(["plugin", "marketplace", "update"], projectRoot, (line) => {
          webview.postMessage({ type: "marketplaceRefreshLine", text: line });
        });
        this._refresh(webview);
      } catch (err) {
        webview.postMessage({ type: "marketplaceRefreshDone", ok: false, error: err.message });
        this._refresh(webview);
      }
    } else if (msg.type === "install") {
      const { id, scope } = msg;
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;
      const installScope = ["local", "project", "user"].includes(scope) ? scope : "local";
      if (!PLUGIN_ID_RE.test(id)) {
        webview.postMessage({ type: "installDone", id, ok: false, error: `Refusing to install "${id}": not a valid name@marketplace plugin id.` });
        return;
      }

      webview.postMessage({ type: "installStart", id });

      try {
        await this._claude(["plugin", "install", id, "--scope", installScope], projectRoot, (line) => {
          webview.postMessage({ type: "installLine", id, text: line });
        });
        webview.postMessage({ type: "installDone", id, ok: true });
        this._refresh(webview);
      } catch (err) {
        webview.postMessage({ type: "installDone", id, ok: false, error: err.message });
      }
    } else if (msg.type === "uninstall") {
      const { id, scope } = msg;
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;
      if (!["local", "project", "user"].includes(scope)) return;
      if (!PLUGIN_ID_RE.test(id)) {
        webview.postMessage({ type: "uninstallDone", id, ok: false, error: `Refusing to uninstall "${id}": not a valid name@marketplace plugin id.` });
        return;
      }

      if (confirmActionsEnabled()) {
        const scopeLabel = { local: "Local", project: "Project", user: "User" }[scope];
        const ok = await vscode.window.showWarningMessage(
          `Uninstall "${id}" from the ${scopeLabel} scope?`,
          { modal: true },
          "Uninstall"
        );
        if (ok !== "Uninstall") {
          this._refresh(webview);
          return;
        }
      }

      webview.postMessage({ type: "uninstallStart", id });

      try {
        await this._claude(["plugin", "uninstall", id, "--scope", scope], projectRoot, (line) => {
          webview.postMessage({ type: "uninstallLine", id, text: line });
        });
        webview.postMessage({ type: "uninstallDone", id, ok: true });
        this._refresh(webview);
      } catch (err) {
        webview.postMessage({ type: "uninstallDone", id, ok: false, error: err.message });
      }
    }
  }

  _getHtml(webview, stylesUri, jsBaseUri) {
    const panelHtmlPath = vscode.Uri.joinPath(
      this._extensionUri,
      "webview",
      "panel.html"
    );
    const iconSvgPath = vscode.Uri.joinPath(
      this._extensionUri,
      "webview",
      "icon.svg"
    );
    const iconSvg = fs.readFileSync(iconSvgPath.fsPath, "utf8").trim();
    let html = fs.readFileSync(panelHtmlPath.fsPath, "utf8");
    html = html.replace(/__CSP_SOURCE__/g, webview.cspSource);
    html = html.replace("__STYLES_URI__", stylesUri.toString());
    html = html.replace(/__JS_BASE__/g, jsBaseUri.toString());
    html = html.replace(/__ICON_SVG__/g, () => iconSvg);
    return html;
  }
}

function activate(context) {
  const provider = new SkillsViewProvider(context.extensionUri, context.workspaceState);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      SkillsViewProvider.viewType,
      provider
    )
  );
}

function deactivate() {}

// VSCode reads only activate and deactivate. `_internals` is for the unit tests in test/.
const _internals = {
  parseSkillFrontmatter,
  buildSections,
  loadInstalledPlugins,
  SkillsViewProvider,
};

module.exports = { activate, deactivate, _internals };
