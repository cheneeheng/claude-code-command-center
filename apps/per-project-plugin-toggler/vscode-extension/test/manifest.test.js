const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { internals } = require("../test-support/load-extension.js");

const root = path.join(__dirname, "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));

test("the manifest and the code agree on the contributed ids", () => {
  const settings = Object.keys(manifest.contributes.configuration.properties);
  assert.deepEqual(settings.filter((k) => !k.startsWith("pluginToggler.")), []);

  const container = manifest.contributes.viewsContainers.activitybar[0].id;
  assert.equal(container, "pluginToggler");
  assert.equal(manifest.contributes.views[container][0].id, internals.SkillsViewProvider.viewType);
});

test("the manifest points at this repository and at files that exist", () => {
  assert.match(manifest.repository.url, /claude-code-command-center/);
  assert.ok(fs.existsSync(path.join(root, manifest.icon)), `${manifest.icon} exists`);
});
