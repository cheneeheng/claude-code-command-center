const test = require("node:test");
const assert = require("node:assert/strict");
const { internals } = require("../test-support/load-extension.js");

const parse = (text) => internals.parseSkillFrontmatter(text, "fallback");

test("inline description", () => {
  const r = parse("---\nname: my-skill\ndescription: Does one thing.\n---\nbody");
  assert.deepEqual(r, { name: "my-skill", description: "Does one thing.", manualOnly: false });
});

test("wrapped description", () => {
  const r = parse("---\nname: s\ndescription: First line\n  second line\n  third line\n---\n");
  assert.equal(r.description, "First line second line third line");
});

test("block-scalar description", () => {
  for (const marker of [">-", ">", "|", "|-"]) {
    const r = parse(`---\nname: s\ndescription: ${marker}\n  First line\n  second line\n---\n`);
    assert.equal(r.description, "First line second line", marker);
  }
});

test("disable-model-invocation marks a skill manual only", () => {
  assert.equal(parse("---\nname: s\ndisable-model-invocation: true\n---\n").manualOnly, true);
  assert.equal(parse('---\nname: s\ndisable-model-invocation: "true"\n---\n').manualOnly, true);
  assert.equal(parse("---\nname: s\ndisable-model-invocation: false\n---\n").manualOnly, false);
  assert.equal(parse("---\nname: s\n---\n").manualOnly, false);
});

test("no frontmatter falls back to the folder name", () => {
  assert.deepEqual(parse("just a body"), { name: "fallback", description: "", manualOnly: false });
});
