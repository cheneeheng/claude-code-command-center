// A stand-in for the `vscode` module, holding only what extension.js touches.
// Tests set `workspace.workspaceFolders`, `config` and `confirmAnswer` directly.
const path = require("path");

const noopWatcher = () => ({
  onDidChange() {},
  onDidCreate() {},
  onDidDelete() {},
  dispose() {},
});

const stub = {
  config: {}, // setting key -> value, read by getConfiguration().get
  confirmAnswer: undefined, // what showWarningMessage resolves to
  workspace: {
    workspaceFolders: undefined, // [{ uri: { fsPath }, name }]
    getConfiguration: () => ({
      get: (key, fallback) => (key in stub.config ? stub.config[key] : fallback),
    }),
    createFileSystemWatcher: noopWatcher,
    onDidChangeWorkspaceFolders: () => ({ dispose() {} }),
  },
  window: {
    showWarningMessage: async () => stub.confirmAnswer,
    registerWebviewViewProvider: () => ({ dispose() {} }),
  },
  Uri: {
    file: (fsPath) => ({ fsPath }),
    joinPath: (base, ...parts) => ({ fsPath: path.join(base.fsPath, ...parts) }),
  },
  RelativePattern: class RelativePattern {
    constructor(base, pattern) {
      this.base = base;
      this.pattern = pattern;
    }
  },
};

module.exports = stub;
