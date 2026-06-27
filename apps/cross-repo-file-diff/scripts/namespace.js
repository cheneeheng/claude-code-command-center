/* ===================================================================
   Vantage v3 — namespace (loaded FIRST)
   Cross-file sharing happens through this single global object, not
   import/export, so the page works opened directly over file://.
   Every module attaches itself to window.Vantage; load order in
   index.html is the dependency contract.
   =================================================================== */

'use strict';

window.Vantage = window.Vantage || {};

/* Shared constants used across modules. */
window.Vantage.IGNORE_LIST = new Set([
  '.git', 'node_modules', 'venv', '.venv', 'target',
  'dist', 'build', '.next', '__pycache__',
]);

window.Vantage.STACK_MARKERS = [
  { files: ['pyproject.toml', 'requirements.txt'], label: 'Python' },
  { files: ['package.json'], label: 'Node' },
  { files: ['Cargo.toml'], label: 'Rust' },
  { files: ['go.mod'], label: 'Go' },
  { files: ['pom.xml', 'build.gradle'], label: 'JVM' },
];

window.Vantage.FALLBACK_WALK_MAX_DEPTH = 3;
