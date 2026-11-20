const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const { internals } = require("../test-support/load-extension.js");

test("the panel HTML allows no inline script", () => {
  const provider = new internals.SkillsViewProvider(
    { fsPath: path.join(__dirname, "..") },
    { get: () => null, update: async () => {} }
  );
  const html = provider._getHtml(
    { cspSource: "vscode-resource:" },
    { toString: () => "vscode-resource:/styles.css" },
    { toString: () => "vscode-resource:/js" }
  );

  const scriptSrc = html.match(/content="[^"]*script-src ([^;]*);/);
  assert.ok(scriptSrc, "the policy has a script-src directive");
  assert.equal(scriptSrc[1], "vscode-resource:");
  assert.deepEqual(html.match(/<script(?![^>]*\ssrc=)[^>]*>/g), null, "every script tag has a src");
  assert.deepEqual(html.match(/\son[a-z]+="/g), null, "no inline event handler");
  assert.match(html, /<html[^>]*\sdata-context="vscode"/);
});
