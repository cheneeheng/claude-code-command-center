const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { internals, vscode, useTempHome, useTempDir, writeJson } = require("../test-support/load-extension.js");

// One open folder with an empty plugin registry, and a provider wired to record its posts.
function setup(t) {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), { plugins: {} });
  vscode.workspace.workspaceFolders = [{ uri: { fsPath: project }, name: "project" }];
  vscode.errors.length = 0;
  t.after(() => (vscode.workspace.workspaceFolders = undefined));
  const posted = [];
  const provider = new internals.SkillsViewProvider(
    { fsPath: path.join(__dirname, "..") },
    { get: () => null, update: async () => {} }
  );
  const send = (msg) => provider._onMessage({ postMessage: (m) => posted.push(m) }, msg);
  const files = {
    local: path.join(project, ".claude", "settings.local.json"),
    project: path.join(project, ".claude", "settings.json"),
    user: path.join(home, ".claude", "settings.json"),
  };
  return { posted, send, files };
}

for (const scope of ["local", "project", "user"]) {
  test(`toggle leaves a malformed ${scope} settings file untouched and shows the error`, async (t) => {
    const { posted, send, files } = setup(t);
    const broken = '{ "permissions": { "allow": ["x"] }, ';
    fs.mkdirSync(path.dirname(files[scope]), { recursive: true });
    fs.writeFileSync(files[scope], broken);

    await send({ type: "toggle", id: "a@m", scope, enabled: false });

    assert.equal(fs.readFileSync(files[scope], "utf8"), broken);
    assert.equal(posted.at(-1).type, "error");
    assert.match(posted.at(-1).message, /Failed to parse/);
  });
}

test("toggle refuses a settings file whose root is not a JSON object", async (t) => {
  const { send, files } = setup(t);
  writeJson(files.project, ["not", "an", "object"]);

  await send({ type: "toggle", id: "a@m", scope: "project", enabled: false });

  assert.deepEqual(JSON.parse(fs.readFileSync(files.project, "utf8")), ["not", "an", "object"]);
});

test("a save that fails tells the user instead of silently snapping the toggle back", async (t) => {
  const { send, files } = setup(t);
  writeJson(files.local, { enabledPlugins: { "a@m": true } });
  t.mock.method(fs, "writeFileSync", () => {
    throw Object.assign(new Error("EACCES: permission denied"), { code: "EACCES" });
  });

  await send({ type: "toggle", id: "a@m", scope: "local", enabled: false });

  assert.equal(vscode.errors.length, 1);
  assert.match(vscode.errors[0], /settings\.local\.json/);
  assert.match(vscode.errors[0], /EACCES/);
});

test("a save that fails midway leaves the old settings intact", async (t) => {
  const { send, files } = setup(t);
  const before = JSON.stringify({ enabledPlugins: { "a@m": true }, permissions: { allow: ["x"] } });
  fs.mkdirSync(path.dirname(files.local), { recursive: true });
  fs.writeFileSync(files.local, before);
  const realWrite = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, data) => {
    realWrite(file, String(data).slice(0, 5)); // the disk fills up after five bytes
    throw Object.assign(new Error("ENOSPC: no space left on device"), { code: "ENOSPC" });
  });

  await send({ type: "toggle", id: "a@m", scope: "local", enabled: false });

  assert.equal(fs.readFileSync(files.local, "utf8"), before);
  assert.deepEqual(fs.readdirSync(path.dirname(files.local)), ["settings.local.json"]);
});

test("toggle ignores a message whose id or enabled has the wrong type", async (t) => {
  const { send, files } = setup(t);
  writeJson(files.local, { enabledPlugins: {} });

  await send({ type: "toggle", id: "a@m", scope: "local", enabled: "yes" });
  await send({ type: "toggle", id: 42, scope: "local", enabled: true });
  await send({ type: "toggle", id: "", scope: "local", enabled: true });

  assert.deepEqual(JSON.parse(fs.readFileSync(files.local, "utf8")), { enabledPlugins: {} });
});
