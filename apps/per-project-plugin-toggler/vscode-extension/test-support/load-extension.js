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

module.exports = { extension, internals: extension._internals, vscode, useTempHome, useTempDir, writeJson };
