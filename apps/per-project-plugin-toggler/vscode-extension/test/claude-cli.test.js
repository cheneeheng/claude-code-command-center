const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {
  internals,
  vscode,
  useTempHome,
  useTempDir,
  writeJson,
  writeFakeClaude,
  usePath,
} = require("../test-support/load-extension.js");

// One open folder, a fake `claude` on PATH, and a provider that records what it posts.
// The real CLI is never run: PATH holds only the fake's folder.
function setup(t) {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  const bin = useTempDir(t, "toggler-bin-");
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), { plugins: {} });
  writeFakeClaude(bin, "fake-claude");
  usePath(t, [bin]);
  vscode.workspace.workspaceFolders = [{ uri: { fsPath: project }, name: "project" }];
  t.after(() => (vscode.workspace.workspaceFolders = undefined));
  const posted = [];
  const provider = new internals.SkillsViewProvider(
    { fsPath: path.join(__dirname, "..") },
    { get: () => null, update: async () => {} }
  );
  const webview = { postMessage: (m) => posted.push(m) };
  const send = (msg) => provider._onMessage(webview, msg);
  const lines = () => posted.filter((m) => m.text).map((m) => m.text.trim());
  return { project, bin, posted, provider, webview, send, lines };
}

test("runs the claude on PATH, not a claude in the project folder", async (t) => {
  const { project, send, lines } = setup(t);
  writeFakeClaude(project, "hijacked");

  await send({ type: "marketplaceRefresh" });

  assert.deepEqual(lines(), ["fake-claude plugin marketplace update"]);
});

test("install passes the id and scope to the CLI and reports success", async (t) => {
  const { send, lines, posted } = setup(t);

  await send({ type: "install", id: "a@m", scope: "project" });

  assert.deepEqual(lines(), ["fake-claude plugin install a@m --scope project"]);
  assert.deepEqual(posted.find((m) => m.type === "installDone"), { type: "installDone", id: "a@m", ok: true });
});

test("refuses a plugin id that starts like a CLI option", async (t) => {
  const { send, lines, posted } = setup(t);

  await send({ type: "install", id: "--help@m", scope: "local" });
  await send({ type: "uninstall", id: "-x@m", scope: "local" });

  assert.deepEqual(lines(), []);
  assert.deepEqual(posted.map((m) => [m.type, m.ok]), [["installDone", false], ["uninstallDone", false]]);
});

test("says the claude CLI was not found when it is not on PATH", async (t) => {
  const { send, posted } = setup(t);
  usePath(t, [useTempDir(t, "toggler-empty-")]);

  await send({ type: "install", id: "a@m", scope: "local" });

  const done = posted.find((m) => m.type === "installDone");
  assert.equal(done.ok, false);
  assert.match(done.error, /claude CLI was not found on PATH/);
});

test("closing the panel stops a CLI call that is still running", { timeout: 30000 }, async (t) => {
  const { provider, posted } = setup(t);
  const pidFile = path.join(useTempDir(t, "toggler-pid-"), "pid");
  process.env.FAKE_CLAUDE_PID_FILE = pidFile;
  let fakePid;
  t.after(() => {
    delete process.env.FAKE_CLAUDE_PID_FILE;
    // Never leave the fake running, whatever the test found. The pid is kept in a
    // variable because the folder holding the pid file is removed by an earlier hook.
    try { process.kill(fakePid); } catch { /* already gone */ }
  });

  // Resolve the view as VSCode does, keeping the callbacks it registers.
  let onMessage, dispose;
  provider.resolveWebviewView({
    webview: {
      asWebviewUri: (uri) => uri.fsPath,
      onDidReceiveMessage: (cb) => (onMessage = cb),
      postMessage: (m) => posted.push(m),
    },
    onDidChangeVisibility() {},
    onDidDispose: (cb) => (dispose = cb),
  });

  const running = onMessage({ type: "install", id: "a@m", scope: "local" });
  while (!(fakePid = Number(fs.existsSync(pidFile) && fs.readFileSync(pidFile, "utf8")))) {
    await new Promise((r) => setTimeout(r, 20));
  }
  dispose();
  const settled = await Promise.race([
    running.then(() => "settled"),
    new Promise((r) => setTimeout(() => r("still running after 5s"), 5000)),
  ]);

  assert.equal(settled, "settled");
  assert.equal(posted.find((m) => m.type === "installDone").ok, false);
});
