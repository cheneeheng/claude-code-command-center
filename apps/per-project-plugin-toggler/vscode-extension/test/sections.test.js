const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const { internals, useTempHome, useTempDir, writeJson } = require("../test-support/load-extension.js");

const noSettings = { local: {}, project: {}, user: {} };

test("buildSections union: a row per id installed at the scope or keyed in its settings", () => {
  const raw = { local: [{ id: "a@m", version: "1.0.0", installPath: "" }], project: [], user: [] };
  const sections = internals.buildSections(raw, { ...noSettings, local: { "b@m": false } });
  assert.deepEqual(
    sections.local.map((p) => [p.id, p.installed, p.enabled]),
    [["a@m", true, true], ["b@m", false, false]]
  );
  assert.deepEqual(sections.project, []);
  assert.equal(sections.local[0].name, "a");
  assert.equal(sections.local[0].marketplace, "m");
});

test("buildSections default enabled: an installed plugin with no settings entry is enabled", () => {
  const raw = { local: [], project: [], user: [{ id: "a@m", version: "", installPath: "" }] };
  const sections = internals.buildSections(raw, { ...noSettings, user: { "a@m": false } });
  assert.equal(sections.user[0].enabled, false);
  assert.equal(internals.buildSections(raw, noSettings).user[0].enabled, true);
});

test("loadInstalledPlugins scope bucketing: local and project entries match the project path", (t) => {
  const home = useTempHome(t);
  const project = useTempDir(t, "toggler-project-");
  const other = useTempDir(t, "toggler-other-");
  writeJson(path.join(home, ".claude", "plugins", "installed_plugins.json"), {
    plugins: {
      "mine@m": [{ scope: "local", projectPath: project, version: "1.0.0", installPath: "/p/mine" }],
      "theirs@m": [{ scope: "local", projectPath: other, version: "1.0.0" }],
      "shared@m": [{ scope: "project", projectPath: project }],
      "global@m": [{ scope: "user", version: "2.0.0" }],
      "odd@m": [{ scope: "managed" }],
    },
  });
  const buckets = internals.loadInstalledPlugins(project);
  assert.deepEqual(buckets.local.map((p) => p.id), ["mine@m"]);
  assert.deepEqual(buckets.project.map((p) => p.id), ["shared@m"]);
  assert.deepEqual(buckets.user.map((p) => p.id), ["global@m"]);
  assert.deepEqual(buckets.local[0], { id: "mine@m", version: "1.0.0", installPath: "/p/mine", scope: "local" });
});
