const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

function _mockPlugins() {
  return {
    local: [
      { id: "ceh-dev-tools@ceh-plugins", version: "1.1.0", installPath: "" },
    ],
    project: [],
    user: [
      { id: "frontend-design@anthropic", version: "2.0.1", installPath: "" },
    ],
    mock: true,
  };
}

function confirmActionsEnabled() {
  return vscode.workspace
    .getConfiguration("skillsToggle")
    .get("confirmActions", false);
}

function normalisePath(p) {
  if (!p) return "";
  try {
    const resolved = path.resolve(p);
    // Windows: lowercase drive letter to normalise "C:\..." vs "c:\..."
    // UNC paths (\\server\share\...) are handled by the platform resolver.
    if (/^[A-Z]:/.test(resolved)) {
      return resolved[0].toLowerCase() + resolved.slice(1);
    }
    return resolved;
  } catch {
    return p;
  }
}

// Cross-reference: loadInstalledPlugins, parseSkillFrontmatter and the skill
// enumeration here are intentionally duplicated in this app's html/server.py and in
// apps/skill-browser/server.py. Keep them in sync — see docs/shared-plugin-logic.md.
function loadInstalledPlugins(projectRoot) {
  const installedPath = path.join(
    os.homedir(),
    ".claude",
    "plugins",
    "installed_plugins.json"
  );
  if (!fs.existsSync(installedPath)) return _mockPlugins();

  try {
    const raw = JSON.parse(fs.readFileSync(installedPath, "utf8"))["plugins"];
    const normProject = normalisePath(projectRoot);
    const buckets = { local: [], project: [], user: [] };

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

function loadSettingsLocal(projectRoot) {
  const p = path.join(projectRoot, ".claude", "settings.local.json");
  if (!fs.existsSync(p)) return {};
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    throw new Error(`Failed to parse ${p}: ${e.message}`);
  }
}

function loadSettingsProject(projectRoot) {
  const p = path.join(projectRoot, ".claude", "settings.json");
  if (!fs.existsSync(p)) return {};
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return {};
  }
}

function loadSettingsUser() {
  const p = path.join(os.homedir(), ".claude", "settings.json");
  if (!fs.existsSync(p)) return {};
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return {};
  }
}

function saveSettingsLocal(projectRoot, settings) {
  const dir = path.join(projectRoot, ".claude");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "settings.local.json"),
    JSON.stringify(settings, null, 2)
  );
}

function saveSettingsProject(projectRoot, settings) {
  const dir = path.join(projectRoot, ".claude");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "settings.json"),
    JSON.stringify(settings, null, 2)
  );
}

function saveSettingsUser(settings) {
  const dir = path.join(os.homedir(), ".claude");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "settings.json"),
    JSON.stringify(settings, null, 2)
  );
}

function parseSkillFrontmatter(text, fallbackName) {
  const fmMatch = text.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!fmMatch) return { name: fallbackName, description: "" };
  const fm = fmMatch[1];

  const nameMatch = fm.match(/^name:\s*(.+)$/m);
  const name = nameMatch ? nameMatch[1].trim() : fallbackName;

  const descBlockMatch = fm.match(
    /^description:\s*(?:>-|>|[|][-]?)?\s*\n([\s\S]*?)(?=\n\S|\s*$)/m
  );
  let description = "";
  if (descBlockMatch) {
    description = descBlockMatch[1]
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .join(" ");
  } else {
    const descInlineMatch = fm.match(/^description:\s*(.+)$/m);
    if (descInlineMatch) description = descInlineMatch[1].trim();
  }

  return { name, description };
}

function loadPluginSkills(installPath) {
  if (!installPath) return [];
  const skillsDir = path.join(installPath, "skills");
  if (!fs.existsSync(skillsDir)) return [];

  return fs
    .readdirSync(skillsDir)
    .filter((name) => fs.statSync(path.join(skillsDir, name)).isDirectory())
    .sort()
    .filter((folderName) =>
      fs.existsSync(path.join(skillsDir, folderName, "SKILL.md"))
    )
    .map((folderName) => {
      const text = fs.readFileSync(
        path.join(skillsDir, folderName, "SKILL.md"),
        "utf8"
      );
      return parseSkillFrontmatter(text, folderName);
    });
}

function loadPluginAgents(installPath) {
  if (!installPath) return [];
  const agentsDir = path.join(installPath, "agents");
  if (!fs.existsSync(agentsDir)) return [];

  return fs
    .readdirSync(agentsDir)
    .filter((f) => f.endsWith(".md"))
    .sort()
    .map((f) => {
      const stem = path.basename(f, ".md");
      const text = fs.readFileSync(path.join(agentsDir, f), "utf8");
      return parseSkillFrontmatter(text, stem);
    });
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
  const mp = path.join(
    os.homedir(),
    ".claude",
    "plugins",
    "known_marketplaces.json"
  );
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


function streamInstall(pluginId, scope, projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn("claude", ["plugin", "install", pluginId, "--scope", scope], {
      cwd: projectRoot,
      stdio: ["ignore", "pipe", "pipe"],
      shell: true,
    });

    let stdoutBuf = "";
    proc.stdout.on("data", (chunk) => {
      stdoutBuf += chunk.toString("utf8");
      const lines = stdoutBuf.split("\n");
      stdoutBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    let stderrBuf = "";
    proc.stderr.on("data", (chunk) => {
      stderrBuf += chunk.toString("utf8");
      const lines = stderrBuf.split("\n");
      stderrBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    proc.on("close", (code) => {
      if (stdoutBuf) onLine(stdoutBuf);
      if (stderrBuf) onLine(stderrBuf);
      if (code === 0) resolve();
      else reject(new Error(`Exit code ${code}`));
    });

    proc.on("error", (err) => {
      reject(err);
    });
  });
}

function streamUninstall(pluginId, scope, projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn("claude", ["plugin", "uninstall", pluginId, "--scope", scope], {
      cwd: projectRoot,
      stdio: ["ignore", "pipe", "pipe"],
      shell: true,
    });

    let stdoutBuf = "";
    proc.stdout.on("data", (chunk) => {
      stdoutBuf += chunk.toString("utf8");
      const lines = stdoutBuf.split("\n");
      stdoutBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    let stderrBuf = "";
    proc.stderr.on("data", (chunk) => {
      stderrBuf += chunk.toString("utf8");
      const lines = stderrBuf.split("\n");
      stderrBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    proc.on("close", (code) => {
      if (stdoutBuf) onLine(stdoutBuf);
      if (stderrBuf) onLine(stderrBuf);
      if (code === 0) resolve();
      else reject(new Error(`Exit code ${code}`));
    });

    proc.on("error", reject);
  });
}

function streamMarketplaceRefresh(projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn("claude", ["plugin", "marketplace", "update"], {
      cwd: projectRoot,
      stdio: ["ignore", "pipe", "pipe"],
      shell: true,
    });

    let stdoutBuf = "", stderrBuf = "";

    proc.stdout.on("data", (chunk) => {
      stdoutBuf += chunk.toString("utf8");
      const lines = stdoutBuf.split("\n");
      stdoutBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    proc.stderr.on("data", (chunk) => {
      stderrBuf += chunk.toString("utf8");
      const lines = stderrBuf.split("\n");
      stderrBuf = lines.pop();
      lines.forEach((l) => onLine(l + "\n"));
    });

    proc.on("close", (code) => {
      if (stdoutBuf) onLine(stdoutBuf);
      if (stderrBuf) onLine(stderrBuf);
      if (code === 0) resolve();
      else reject(new Error(`Exit code ${code}`));
    });

    proc.on("error", reject);
  });
}

class SkillsViewProvider {
  static viewType = "skillsToggle.pluginList";

  constructor(extensionUri, context) {
    this._extensionUri = extensionUri;
    this._context = context;
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
    this._refresh(webviewView.webview);
    webviewView.webview.onDidReceiveMessage((msg) =>
      this._onMessage(webviewView.webview, msg)
    );
    webviewView.onDidChangeVisibility(() => {
      if (webviewView.visible) this._refresh(webviewView.webview);
    });

    // File watchers — auto-refresh on settings or installed_plugins change
    const folders = vscode.workspace.workspaceFolders;
    if (folders && folders.length > 0) {
      const installedPath = path.join(
        os.homedir(),
        ".claude",
        "plugins",
        "installed_plugins.json"
      );

      const onchange = () => this._refresh(webviewView.webview);

      // Local + project settings — workspace-relative
      const settingsWatcher = vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(folders[0], ".claude/settings.local.json")
      );
      const projectSettingsWatcher = vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(folders[0], ".claude/settings.json")
      );
      // User settings + install registry — absolute paths (outside the workspace)
      const userSettingsWatcher = vscode.workspace.createFileSystemWatcher(
        path.join(os.homedir(), ".claude", "settings.json")
      );
      const installedWatcher =
        vscode.workspace.createFileSystemWatcher(installedPath);

      for (const w of [settingsWatcher, projectSettingsWatcher, userSettingsWatcher, installedWatcher]) {
        w.onDidChange(onchange);
        w.onDidCreate(onchange);
        w.onDidDelete(onchange);
        this._context.subscriptions.push(w);
      }
    }
  }

  _projectRoot() {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || folders.length === 0) return null;
    const p = folders[0].uri.fsPath;
    // VSCode returns lowercase drive letters on Windows; normalize to uppercase
    // so spawn's cwd matches what the CLI writes to installed_plugins.json.
    if (/^[a-z]:/.test(p)) return p[0].toUpperCase() + p.slice(1);
    return p;
  }

  _refresh(webview) {
    const projectRoot = this._projectRoot();
    if (!projectRoot) {
      webview.postMessage({ type: "error", message: "No workspace folder open." });
      return;
    }
    try {
      const raw = loadInstalledPlugins(projectRoot);
      const isMock = raw.mock || false;

      const settings = {
        local: loadSettingsLocal(projectRoot).enabledPlugins || {},
        project: loadSettingsProject(projectRoot).enabledPlugins || {},
        user: loadSettingsUser().enabledPlugins || {},
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
        mock: isMock,
      });
    } catch (e) {
      webview.postMessage({ type: "error", message: e.message });
    }
  }

  async _onMessage(webview, msg) {
    if (msg.type === "toggle") {
      const { id, enabled, scope } = msg;
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;
      if (!["local", "project", "user"].includes(scope)) return;

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

      const load = { local: loadSettingsLocal, project: loadSettingsProject, user: loadSettingsUser };
      const settings = scope === "user" ? load.user() : load[scope](projectRoot);
      if (!settings.enabledPlugins) settings.enabledPlugins = {};
      settings.enabledPlugins[id] = enabled;
      if (scope === "local") saveSettingsLocal(projectRoot, settings);
      else if (scope === "project") saveSettingsProject(projectRoot, settings);
      else saveSettingsUser(settings);

      this._refresh(webview);
    } else if (msg.type === "marketplaceRefresh") {
      const projectRoot = this._projectRoot();
      if (!projectRoot) return;

      webview.postMessage({ type: "marketplaceRefreshStart" });
      try {
        await streamMarketplaceRefresh(projectRoot, (line) => {
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

      webview.postMessage({ type: "installStart", id });

      try {
        await streamInstall(id, installScope, projectRoot, (line) => {
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
        await streamUninstall(id, scope, projectRoot, (line) => {
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
    html = html.replace("__STYLES_URI__", stylesUri.toString());
    html = html.replace(/__JS_BASE__/g, jsBaseUri.toString());
    html = html.replace(/__ICON_SVG__/g, () => iconSvg);
    return html;
  }
}

function activate(context) {
  const provider = new SkillsViewProvider(context.extensionUri, context);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      SkillsViewProvider.viewType,
      provider
    )
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
