const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { internals, vscode, useTempHome, useTempDir, writeJson } = require("../test-support/load-extension.js");

// Posts one `ready` message for an open folder and returns what the panel was sent.
async function loadPanel(t, project) {
  vscode.workspace.workspaceFolders = [{ uri: { fsPath: project }, name: "project" }];
  t.after(() => (vscode.workspace.workspaceFolders = undefined));
  const posted = [];
  const provider = new internals.SkillsViewProvider(
    { fsPath: path.join(__dirname, "..") },
    { get: () => null, update: async () => {} }
  );
  await provider._onMessage({ postMessage: (m) => posted.push(m) }, { type: "ready" });
  return posted.at(-1);
}

test("a block-scalar description with CRLF line endings is read in full", () => {
  const text = "---\r\nname: s\r\ndescription: >-\r\n  First line\r\n  second line\r\n---\r\nbody\r\n";
  assert.deepEqual(internals.parseSkillFrontmatter(text, "fallback"), {
    name: "s",
    description: "First line second line",
    manualOnly: false,
  });
});

test("an inline description and manual-only flag with CRLF line endings are read", () => {
  const text = "---\r\nname: s\r\ndescription: Does one thing.\r\ndisable-model-invocation: true\r\n---\r\n";
  assert.deepEqual(internals.parseSkillFrontmatter(text, "fallback"), {
    name: "s",
    description: "Does one thing.",
    manualOnly: true,
  });
});

test("one unreadable skill does not break the panel", async (t) => {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  const plugin = useTempDir(t, "toggler-plugin-");
  fs.mkdirSync(path.join(plugin, "skills", "good"), { recursive: true });
  fs.writeFileSync(path.join(plugin, "skills", "good", "SKILL.md"), "---\nname: good\n---\n");
  // SKILL.md is a folder here, so reading it fails, as a broken link or a locked file would.
  fs.mkdirSync(path.join(plugin, "skills", "broken", "SKILL.md"), { recursive: true });
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), {
    plugins: { "a@m": [{ scope: "user", installPath: plugin }] },
  });

  const msg = await loadPanel(t, project);

  assert.equal(msg.type, "load");
  assert.deepEqual(msg.plugins.user[0].skills.map((s) => s.name), ["good"]);
});

test("a missing plugin registry shows no plugins, not mock ones", async (t) => {
  useTempHome(t);
  const project = useTempDir(t, "toggler-project-");

  const msg = await loadPanel(t, project);

  assert.equal(msg.type, "load");
  assert.deepEqual(msg.plugins, { local: [], project: [], user: [] });
  assert.equal("mock" in msg, false);
});

test("a project path that differs only in case matches on a case-insensitive file system", (t) => {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-Project-");
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), {
    plugins: { "a@m": [{ scope: "local", projectPath: project.toUpperCase() }] },
  });

  const found = internals.loadInstalledPlugins(project.toLowerCase()).local.map((p) => p.id);

  // Windows and macOS fold case in paths. Linux does not, so there the two are different folders.
  const foldsCase = process.platform === "win32" || process.platform === "darwin";
  assert.deepEqual(found, foldsCase ? ["a@m"] : []);
});

test("CLAUDE_CONFIG_DIR moves the registry and the user settings", async (t) => {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  const config = useTempDir(t, "toggler-config-");
  process.env.CLAUDE_CONFIG_DIR = config; // useTempHome restores it
  writeJson(path.join(config, "plugins", "installed_plugins.json"), {
    plugins: { "moved@m": [{ scope: "user" }] },
  });
  writeJson(path.join(config, "settings.json"), { enabledPlugins: { "moved@m": false } });
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), {
    plugins: { "default@m": [{ scope: "user" }] },
  });

  const msg = await loadPanel(t, project);

  assert.deepEqual(msg.plugins.user.map((p) => [p.id, p.enabled]), [["moved@m", false]]);
});
