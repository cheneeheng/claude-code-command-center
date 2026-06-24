/* ===================================================================
   Vantage.Editor — compose a vscode://file/ URI from the manual root path
   The File System Access API never exposes the picked folder's absolute path,
   so the root path is supplied separately (ITER_04) and held here.
   =================================================================== */

'use strict';

window.Vantage.Editor = {
  // Optional absolute projects-root path. UI keeps this in sync with Persist.
  rootPath: null,

  setRootPath(str) { this.rootPath = str || null; },

  /**
   * Compose vscode://file/<rootPath>/<repoName>. Returns null when rootPath is
   * unset (keeps the Open-in-VSCode button disabled).
   *
   * Slash handling: backslashes → forward slashes; trailing slashes trimmed;
   * the path is forced to start with "/" so Windows drive paths become
   * vscode://file/C:/... and POSIX paths become vscode://file/Users/...
   */
  vscodeUri(repoName) {
    if (!this.rootPath) return null;
    let p = String(this.rootPath).trim().replace(/\\/g, '/').replace(/\/+$/, '');
    if (p === '') return null;
    if (!p.startsWith('/')) p = '/' + p;
    return encodeURI('vscode://file' + p + '/' + repoName);
  },
};
