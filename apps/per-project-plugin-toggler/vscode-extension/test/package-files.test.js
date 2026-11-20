const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");

test("the prepublish script copies the root LICENSE and the member CHANGELOG into the package", () => {
  execFileSync(process.execPath, [path.join(root, "scripts", "copy-package-files.js")]);

  const read = (...parts) => fs.readFileSync(path.join(root, ...parts), "utf8");
  assert.equal(read("LICENSE"), read("..", "..", "..", "LICENSE"));
  assert.equal(read("CHANGELOG.md"), read("..", "CHANGELOG.md"));
  assert.ok(fs.statSync(path.join(root, "dist")).isDirectory());
});
