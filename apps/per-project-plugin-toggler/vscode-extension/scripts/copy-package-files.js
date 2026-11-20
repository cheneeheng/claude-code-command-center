// Run by vsce before every package and publish (the vscode:prepublish script).
// The VSIX must carry a LICENSE and a CHANGELOG.md, and the repo keeps one copy of each:
// the root LICENSE and the member CHANGELOG.md. Both copies made here are git-ignored.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
fs.copyFileSync(path.join(root, "..", "..", "..", "LICENSE"), path.join(root, "LICENSE"));
fs.copyFileSync(path.join(root, "..", "CHANGELOG.md"), path.join(root, "CHANGELOG.md"));
// vsce does not create the folder its --out file goes in.
fs.mkdirSync(path.join(root, "dist"), { recursive: true });
