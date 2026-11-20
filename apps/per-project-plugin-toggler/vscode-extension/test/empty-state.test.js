const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

// render.js is a classic browser script. It runs here against the few globals
// renderPlugins() touches: elements are plain objects with a style and innerHTML.
function renderWith(state) {
  const elements = {};
  const el = (id) => (elements[id] ??= { style: {}, innerHTML: "" });
  const context = {
    SCOPES: ["local", "project", "user"],
    state,
    statusText: null,
    showStatus: (html) => (context.statusText = html),
    esc: String,
    document: { getElementById: el, querySelectorAll: () => [] },
  };
  const source = fs.readFileSync(path.join(__dirname, "..", "webview", "js", "render.js"), "utf8");
  vm.runInNewContext(source, context);
  context.renderPlugins();
  return { el, context };
}

test("a project with no plugins still offers the install button", () => {
  const { el, context } = renderWith({ local: [], project: [], user: [] });

  assert.notEqual(el("bulk-actions").style.display, "none", "the row holding the install button is shown");
  assert.equal(el("bulk-toggles").style.display, "none", "Enable all and Disable all have nothing to act on");
  assert.equal(el("plugin-sections").style.display, "none");
  assert.match(context.statusText, /No plugins found/);
});

test("a project with plugins shows the install button and the bulk toggles", () => {
  const plugin = { id: "a@m", name: "a", marketplace: "m", enabled: true, installed: true };
  const { el } = renderWith({ local: [plugin], project: [], user: [] });

  assert.equal(el("bulk-actions").style.display, "flex");
  assert.equal(el("bulk-toggles").style.display, "");
  assert.match(el("local-list").innerHTML, /data-action="uninstall"/);
});
