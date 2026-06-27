/* ===================================================================
   Vantage.Scanner — enumerate repos, detect stack, last-activity, trees
   Depends on: Vantage.Persist, Vantage.IGNORE_LIST, Vantage.STACK_MARKERS,
   Vantage.FALLBACK_WALK_MAX_DEPTH (loaded earlier in index.html).
   =================================================================== */

'use strict';

window.Vantage.Scanner = {
  // Open the OS directory picker (must run inside a user gesture), store the
  // handle, then scan it. Returns Repo[] (or null if the user cancelled).
  async chooseRoot() {
    let handle;
    try { handle = await window.showDirectoryPicker({ mode: 'readwrite', id: 'vantage-root' }); }
    catch (err) { return null; /* cancelled */ }
    await window.Vantage.Persist.saveHandle(handle);
    const repos = await this.scanRoot(handle);
    return { handle, repos };
  },

  async scanRoot(dirHandle) {
    const Scanner = this;
    const dirEntries = [];
    for await (const [name, handle] of dirHandle.entries()) {
      if (handle.kind === 'directory') dirEntries.push({ name, handle });
    }

    // Per-repo metadata gathered concurrently — never awaited in a loop.
    const repos = await Promise.all(
      dirEntries.map(async ({ name, handle }) => {
        const [stack, lastActivity] = await Promise.all([
          Scanner.detectStack(handle),
          Scanner.lastActivity(handle),
        ]);
        return { name, dirHandle: handle, stack, lastActivity, fileTree: null };
      })
    );

    await window.Vantage.Persist.saveCache({
      scannedAt: Date.now(),
      repos: repos.map((r) => ({ name: r.name, stack: r.stack, lastActivity: r.lastActivity })),
    });

    return repos;
  },

  async detectStack(repoHandle) {
    const stacks = [];
    for (const marker of window.Vantage.STACK_MARKERS) {
      for (const fileName of marker.files) {
        if (await this._hasFile(repoHandle, fileName)) { stacks.push(marker.label); break; }
      }
    }
    return stacks;
  },

  async _hasFile(dirHandle, name) {
    try { await dirHandle.getFileHandle(name); return true; }
    catch (err) { return false; }
  },

  // Fallback chain: .git/logs/HEAD mtime → .git/HEAD → shallow ignore-listed
  // walk (newest file mtime). Returns epoch ms, or null (card shows "—").
  async lastActivity(repoHandle) {
    try {
      const gitDir = await repoHandle.getDirectoryHandle('.git');
      try {
        const logsDir = await gitDir.getDirectoryHandle('logs');
        const headFile = await logsDir.getFileHandle('HEAD');
        return (await headFile.getFile()).lastModified;
      } catch (err) { /* fall through */ }
      try {
        const headFile = await gitDir.getFileHandle('HEAD');
        return (await headFile.getFile()).lastModified;
      } catch (err) { /* fall through */ }
    } catch (err) { /* no .git — fall through to walk */ }

    try { return await this._newestMtimeWalk(repoHandle, 0); }
    catch (err) { return null; }
  },

  async _newestMtimeWalk(dirHandle, depth) {
    const maxDepth = window.Vantage.FALLBACK_WALK_MAX_DEPTH;
    let newest = null;
    if (depth > maxDepth) return newest;

    for await (const [name, handle] of dirHandle.entries()) {
      if (window.Vantage.IGNORE_LIST.has(name)) continue;

      if (handle.kind === 'file') {
        try {
          const file = await handle.getFile();
          if (newest === null || file.lastModified > newest) newest = file.lastModified;
        } catch (err) { /* skip unreadable file */ }
      } else if (handle.kind === 'directory' && depth < maxDepth) {
        const childNewest = await this._newestMtimeWalk(handle, depth + 1);
        if (childNewest !== null && (newest === null || childNewest > newest)) newest = childNewest;
      }
    }
    return newest;
  },

  // Lazy file tree, memoised on the Repo. Ignore-listed dirs are skipped
  // *during* enumeration so node_modules etc. are never descended.
  async readTree(repo) {
    const root = await this._readTreeNode(repo.dirHandle, repo.name);
    repo.fileTree = root;
    return root;
  },

  async _readTreeNode(dirHandle, name) {
    const node = { name, kind: 'dir', handle: dirHandle, children: [] };

    const entries = [];
    for await (const [childName, childHandle] of dirHandle.entries()) {
      if (childHandle.kind === 'directory' && window.Vantage.IGNORE_LIST.has(childName)) continue;
      entries.push({ name: childName, handle: childHandle });
    }

    entries.sort((a, b) => {
      const aIsDir = a.handle.kind === 'directory';
      const bIsDir = b.handle.kind === 'directory';
      if (aIsDir !== bIsDir) return aIsDir ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    for (const entry of entries) {
      if (entry.handle.kind === 'directory') {
        node.children.push({ name: entry.name, kind: 'dir', handle: entry.handle, children: null });
      } else {
        node.children.push({ name: entry.name, kind: 'file', handle: entry.handle });
      }
    }
    return node;
  },

  // Populate a directory node's children on first expand.
  async readChildren(dirNode) {
    if (dirNode.children !== null) return dirNode.children;
    const populated = await this._readTreeNode(dirNode.handle, dirNode.name);
    dirNode.children = populated.children;
    return dirNode.children;
  },
};
