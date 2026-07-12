// Unified-diff (`git diff`) patch parser + renderer — no deps, the patch text is
// already the diff; this only turns it into a per-file, gutter'd table.
window.RT = window.RT || {};

RT.diff = {
  // Parses `git diff` unified-patch text into File[]: { path, binary, hunks }.
  // hunks: { header, rows }[]; rows: { kind: "add"|"del"|"ctx", text, oldNum, newNum }.
  parse(patch) {
    const files = [];
    let file = null;
    let hunk = null;
    let oldLine = 0, newLine = 0;
    for (const line of (patch || "").split("\n")) {
      const fileMatch = /^diff --git a\/(.*) b\/(.*)$/.exec(line);
      if (fileMatch) {
        file = { path: fileMatch[2] || fileMatch[1], binary: false, hunks: [] };
        files.push(file);
        hunk = null;
        continue;
      }
      if (!file) continue;
      if (line.startsWith("Binary files ")) { file.binary = true; continue; }
      const hunkMatch = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/.exec(line);
      if (hunkMatch) {
        oldLine = parseInt(hunkMatch[1], 10);
        newLine = parseInt(hunkMatch[2], 10);
        hunk = { header: line, rows: [] };
        file.hunks.push(hunk);
        continue;
      }
      if (!hunk) continue; // file-level metadata (index/mode/rename lines) — not rendered
      if (line.startsWith("+")) hunk.rows.push({ kind: "add", text: line.slice(1), newNum: newLine++ });
      else if (line.startsWith("-")) hunk.rows.push({ kind: "del", text: line.slice(1), oldNum: oldLine++ });
      else if (line.startsWith("\\")) continue; // "\ No newline at end of file"
      else hunk.rows.push({ kind: "ctx", text: line.slice(1), oldNum: oldLine++, newNum: newLine++ });
    }
    return files;
  },

  // Renders patch text as a DOM fragment: one .diff-file card per file, each with
  // a two-gutter (old/new line number) table and hunk-header divider rows.
  render(patch) {
    const h = RT.h;
    const frag = document.createDocumentFragment();
    for (const file of this.parse(patch)) {
      const card = h("div", { class: "diff-file" }, h("div", { class: "diff-file-head" }, file.path));
      if (file.binary) {
        card.append(h("div", { class: "empty" }, "binary file"));
      } else {
        const rows = [];
        for (const hunk of file.hunks) {
          rows.push(h("tr", { class: "diff-hunk-row" }, h("td", { colspan: "4" }, hunk.header)));
          for (const row of hunk.rows) {
            rows.push(h("tr", { class: `diff-row-${row.kind}` },
              h("td", { class: "diff-num" }, row.oldNum ?? ""),
              h("td", { class: "diff-num" }, row.newNum ?? ""),
              h("td", { class: "diff-marker" }, row.kind === "add" ? "+" : row.kind === "del" ? "−" : ""),
              h("td", { class: "diff-text" }, row.text)));
          }
        }
        card.append(h("table", { class: "diff-table" }, h("tbody", {}, rows)));
      }
      frag.append(card);
    }
    return frag;
  },
};
