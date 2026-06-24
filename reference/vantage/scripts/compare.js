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
  diff(textA, textB) {
    const linesA = textA.length === 0 ? [] : textA.split('\n');
    const linesB = textB.length === 0 ? [] : textB.split('\n');
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
};
