// Loads extension.js without VSCode: `require("vscode")` resolves to the stub.
// This is the one place that knows the module is faked. Fix records that need
// another seam (such as a fake child_process.spawn) extend this file.
const Module = require("module");
const fs = require("fs");
const os = require("os");
const path = require("path");

const stubPath = path.join(__dirname, "vscode-stub.js");
const resolveFilename = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  if (request === "vscode") return stubPath;
  return resolveFilename.call(this, request, ...rest);
};

const vscode = require(stubPath);
const extension = require("../extension.js");

// Points os.homedir() at a fresh temp folder for one test and restores it after,
// so no test reads or writes the real ~/.claude. CLAUDE_CONFIG_DIR is cleared too.
function useTempHome(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "toggler-home-"));
  const keys = ["HOME", "USERPROFILE", "CLAUDE_CONFIG_DIR"];
  const saved = Object.fromEntries(keys.map((k) => [k, process.env[k]]));
  process.env.HOME = home;
  process.env.USERPROFILE = home;
  delete process.env.CLAUDE_CONFIG_DIR;
  t.after(() => {
    for (const k of keys) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
    fs.rmSync(home, { recursive: true, force: true });
  });
  return home;
}

// A temp folder removed after the test, for a fake project or plugin.
function useTempDir(t, prefix = "toggler-") {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
}

// Writes a fake `claude` into dir: a script that prints `<tag> <its arguments>`. When
// FAKE_CLAUDE_PID_FILE is set it also writes its pid there and never exits, to stand in
// for a CLI call that hangs. On Windows it is a .cmd shim, as an npm install of the CLI is.
function writeFakeClaude(dir, tag) {
  fs.mkdirSync(dir, { recursive: true });
  const script = path.join(dir, "claude-fake.js");
  fs.writeFileSync(
    script,
    `console.log(${JSON.stringify(tag)} + " " + process.argv.slice(2).join(" "));
if (process.env.FAKE_CLAUDE_PID_FILE) {
  require("fs").writeFileSync(process.env.FAKE_CLAUDE_PID_FILE, String(process.pid));
  setInterval(() => {}, 1000);
}
`
  );
  if (process.platform === "win32") {
    fs.writeFileSync(
      path.join(dir, "claude.cmd"),
      `@echo off\r\n"${process.execPath}" "%~dp0claude-fake.js" %*\r\n`
    );
  } else {
    const shim = path.join(dir, "claude");
    fs.writeFileSync(shim, `#!/bin/sh\nexec "${process.execPath}" "$(dirname "$0")/claude-fake.js" "$@"\n`);
    fs.chmodSync(shim, 0o755);
  }
}

// Sets PATH for one test and restores it after. Pass the folders to search, in order.
// NoDefaultCurrentDirectoryInExePath is cleared as well: some shells set it, and it stops
// cmd.exe from searching the current folder, which a default Windows session does.
function usePath(t, dirs) {
  const saved = { PATH: process.env.PATH, guard: process.env.NoDefaultCurrentDirectoryInExePath };
  process.env.PATH = dirs.join(path.delimiter);
  delete process.env.NoDefaultCurrentDirectoryInExePath;
  t.after(() => {
    process.env.PATH = saved.PATH;
    if (saved.guard !== undefined) process.env.NoDefaultCurrentDirectoryInExePath = saved.guard;
  });
}

module.exports = {
  extension,
  internals: extension._internals,
  vscode,
  useTempHome,
  useTempDir,
  writeJson,
  writeFakeClaude,
  usePath,
};
