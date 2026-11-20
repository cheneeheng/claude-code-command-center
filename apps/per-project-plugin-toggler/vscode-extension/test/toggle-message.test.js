const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { internals, vscode, useTempHome, useTempDir, writeJson } = require("../test-support/load-extension.js");

test("toggle message writes settings.local.json and reloads the panel", async (t) => {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), { plugins: {} });
  writeJson(path.join(project, ".claude", "settings.local.json"), { permissions: { allow: ["x"] } });
  vscode.workspace.workspaceFolders = [{ uri: { fsPath: project }, name: "project" }];
  t.after(() => (vscode.workspace.workspaceFolders = undefined));

  const posted = [];
  const provider = new internals.SkillsViewProvider(
    { fsPath: path.join(__dirname, "..") },
    { get: () => null, update: async () => {} }
  );
  await provider._onMessage(
    { postMessage: (m) => posted.push(m) },
    { type: "toggle", id: "a@m", scope: "local", enabled: false }
  );

  const saved = JSON.parse(fs.readFileSync(path.join(project, ".claude", "settings.local.json"), "utf8"));
  assert.deepEqual(saved, { permissions: { allow: ["x"] }, enabledPlugins: { "a@m": false } });
  const last = posted.at(-1);
  assert.equal(last.type, "load");
  assert.deepEqual(last.plugins.local.map((p) => [p.id, p.enabled]), [["a@m", false]]);
});
