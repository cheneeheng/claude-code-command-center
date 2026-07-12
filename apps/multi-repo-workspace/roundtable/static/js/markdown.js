// The single markdown entry point: render(mdText) -> sanitized HTML.
// Every markdown surface goes through here — no second renderer, ever.
window.RT = window.RT || {};

RT.md = {
  render(mdText) {
    const raw = marked.parse(mdText || "", { gfm: true, async: false });
    return DOMPurify.sanitize(raw); // default allowlist
  },
  into(el, mdText) {
    el.innerHTML = this.render(mdText);
  },
  // Lenient frontmatter split — mirrors roundtable/frontmatter.py's flat `key: value`
  // reader (display-only; the app never writes plan/file content). Returns [meta, body].
  splitFrontmatter(text) {
    const normalized = (text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    if (!normalized.startsWith("---\n") && normalized !== "---") return [{}, text || ""];
    const lines = normalized.split("\n");
    let end = -1;
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") { end = i; break; }
    }
    if (end === -1) return [{}, text || ""];
    const meta = {};
    for (const line of lines.slice(1, end)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#") || !line.includes(":")) continue;
      const idx = line.indexOf(":");
      const key = line.slice(0, idx).trim();
      const value = line.slice(idx + 1).trim().replace(/^"+|"+$/g, "").replace(/^'+|'+$/g, "");
      if (key) meta[key] = value;
    }
    return [meta, lines.slice(end + 1).join("\n")];
  },
  // GitHub-style key/value table for a frontmatter meta object, or null if empty.
  metaTable(meta) {
    const entries = Object.entries(meta || {});
    if (!entries.length) return null;
    return RT.h("table", {},
      RT.h("tbody", {}, entries.map(([key, value]) => RT.h("tr", {}, RT.h("th", {}, key), RT.h("td", {}, value)))));
  },
  // The meta table wrapped in a labeled card — the shared frontmatter presentation
  // used by both the plan view and any rendered-markdown file. Null if no frontmatter.
  metaCard(meta, label = "Frontmatter") {
    const table = this.metaTable(meta);
    return table ? RT.h("div", { class: "card my-4" }, RT.h("span", { class: "eyebrow mb-2" }, label), table) : null;
  },
  // Splits frontmatter off mdText, renders it as a card+table, and renders the
  // remaining body as markdown — both appended into container (replacing its children).
  intoWithFrontmatter(container, mdText) {
    const [meta, body] = this.splitFrontmatter(mdText);
    const card = this.metaCard(meta);
    const mdDiv = document.createElement("div");
    mdDiv.className = "md-body";
    this.into(mdDiv, body);
    container.replaceChildren(...(card ? [card] : []), mdDiv);
  },
};
