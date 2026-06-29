/* ===================================================================
   Vantage.Compare — line-based LCS diff (hand-rolled, no deps)
   =================================================================== */

'use strict';

window.Vantage.Compare = {
  // NUL byte in the first ~8KB, or a failed strict UTF-8 decode → treat as binary.
  looksBinary(arrayBuffer) {
    const bytes = new Uint8Array(arrayBuffer.slice(0, 8192));
    for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return true;
    try { new TextDecoder('utf-8', { fatal: true }).decode(arrayBuffer); }
    catch (err) { return true; }
    return false;
  },

  // Line-based LCS diff. Returns DiffLine[]: { kind: 'add'|'del'|'same', text }.
  // Splits on any EOL (CRLF / CR / LF) so the same content compares equal across
  // a Windows/Unix line-ending mismatch instead of every line reading as changed.
  diff(textA, textB) {
    const SPLIT = /\r\n|\r|\n/;
    const linesA = textA.length === 0 ? [] : textA.split(SPLIT);
    const linesB = textB.length === 0 ? [] : textB.split(SPLIT);
    const n = linesA.length;
    const m = linesB.length;

    const lcs = new Array(n + 1);
    for (let i = 0; i <= n; i++) lcs[i] = new Int32Array(m + 1);
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        lcs[i][j] = linesA[i] === linesB[j]
          ? lcs[i + 1][j + 1] + 1
          : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }

    const result = [];
    let i = 0, j = 0;
    while (i < n && j < m) {
      if (linesA[i] === linesB[j]) { result.push({ kind: 'same', text: linesA[i] }); i++; j++; }
      else if (lcs[i + 1][j] >= lcs[i][j + 1]) { result.push({ kind: 'del', text: linesA[i] }); i++; }
      else { result.push({ kind: 'add', text: linesB[j] }); j++; }
    }
    while (i < n) { result.push({ kind: 'del', text: linesA[i] }); i++; }
    while (j < m) { result.push({ kind: 'add', text: linesB[j] }); j++; }
    return result;
  },

  // Word-level diff of two single lines (a replaced del/add pair), reusing the
  // same LCS over whitespace/non-whitespace tokens. Returns { a, b }, each a
  // Segment[]: { text, changed } with adjacent same-flag tokens merged so the
  // renderer wraps whole changed runs in one highlight span. Pathologically long
  // lines (e.g. minified) skip the O(words^2) pass and mark the whole line changed.
  wordDiff(lineA, lineB) {
    const ta = lineA.match(/\s+|\S+/g) || [];
    const tb = lineB.match(/\s+|\S+/g) || [];
    const n = ta.length, m = tb.length;
    if (n > 400 || m > 400) {
      return { a: [{ text: lineA, changed: true }], b: [{ text: lineB, changed: true }] };
    }

    const lcs = new Array(n + 1);
    for (let i = 0; i <= n; i++) lcs[i] = new Int32Array(m + 1);
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        lcs[i][j] = ta[i] === tb[j]
          ? lcs[i + 1][j + 1] + 1
          : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }

    const a = [], b = [];
    const push = (segs, text, changed) => {
      const last = segs[segs.length - 1];
      if (last && last.changed === changed) last.text += text;
      else segs.push({ text, changed });
    };
    let i = 0, j = 0;
    while (i < n && j < m) {
      if (ta[i] === tb[j]) { push(a, ta[i], false); push(b, tb[j], false); i++; j++; }
      else if (lcs[i + 1][j] >= lcs[i][j + 1]) { push(a, ta[i], true); i++; }
      else { push(b, tb[j], true); j++; }
    }
    while (i < n) { push(a, ta[i], true); i++; }
    while (j < m) { push(b, tb[j], true); j++; }
    return { a, b };
  },
};
