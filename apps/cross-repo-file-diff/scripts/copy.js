/* ===================================================================
   Vantage.Copy — overwrite-confirmed write of one file onto another
   The only destructive action in the app; writes stay within the picked root.
   =================================================================== */

'use strict';

window.Vantage.Copy = {
  // Walk the destination repo's handle to the chosen file's parent directory,
  // creating intermediate dirs as needed.
  async resolveDestDir(repoDirHandle, pathParts) {
    let dir = repoDirHandle;
    for (let k = 0; k < pathParts.length - 1; k++) {
      dir = await dir.getDirectoryHandle(pathParts[k], { create: true });
    }
    return dir;
  },

  async destExists(dirHandle, name) {
    try { await dirHandle.getFileHandle(name); return true; }
    catch (err) { return false; }
  },

  async copyFile(srcFileHandle, dstDirHandle, name) {
    const contents = await (await srcFileHandle.getFile()).arrayBuffer();
    const dstFileHandle = await dstDirHandle.getFileHandle(name, { create: true });
    const writable = await dstFileHandle.createWritable();
    try { await writable.write(contents); }
    finally { await writable.close(); }
    return dstFileHandle;
  },
};
