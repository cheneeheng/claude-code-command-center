/* ===================================================================
   Vantage.UI — top-level state, DOM wiring, and all rendering
   (board, file tree, selection bar, diff sidebar, puck, highlights, modals).
   Depends on every other Vantage module; app.js boots it last.
   =================================================================== */

'use strict';

window.Vantage.UI = {
  // ---- State ----
  rootHandle: null,
  rootPath: null,                                    // absolute path string | null
  repos: [],                                         // Repo[]
  filterText: '',
  sortMode: 'last-activity',                         // 'last-activity' | 'alphabetical' | 'stack'
  selection: { sideA: null, sideB: null },           // { repoName, path, handle } | null
  nextSide: 'A',
  sidebarMode: 'open',                               // 'open' | 'minimized' (consulted only once both sides set)
  lastDiff: null,                                    // { keyA, keyB, lines? }
  activeRepoName: null,                              // currently expanded/focused card (.is-active)

  el: {},

  /* ---- Init ---- */
  async init() {
    this.cacheDom();
    this.bindEvents();
    try { this.rootPath = await window.Vantage.Persist.loadRootPath(); } catch (err) { this.rootPath = null; }
    window.Vantage.Editor.setRootPath(this.rootPath);
    await this.tryReopen();
  },

  cacheDom() {
    const id = (x) => document.getElementById(x);
    this.el.filterInput = id('filter-input');
    this.el.sortSelect = id('sort-select');
    this.el.rootPathBtn = id('root-path-btn');
    this.el.rescanBtn = id('rescan-btn');
    this.el.chooseFolderBtn = id('choose-folder-btn');
    this.el.reconnectBtn = id('reconnect-btn');
    this.el.emptyChooseFolderBtn = id('empty-choose-folder-btn');
    this.el.noticeBar = id('notice-bar');

    this.el.selectionBar = id('selection-bar');
    this.el.selectionSlots = id('selection-slots');
    this.el.selectionNext = id('selection-next');
    this.el.selectionSwapBtn = id('selection-swap-btn');
    this.el.selectionClearBtn = id('selection-clear-btn');

    this.el.emptyState = id('empty-state');
    this.el.board = id('board');

    this.el.sidebar = id('diff-sidebar');
    this.el.sidebarSides = id('sidebar-sides');
    this.el.sidebarSwapBtn = id('sidebar-swap-btn');
    this.el.sidebarMinimizeBtn = id('sidebar-minimize-btn');
    this.el.diffStatus = id('diff-status');
    this.el.diffView = id('diff-view');
    this.el.sidebarFooter = id('sidebar-footer');
    this.el.copyAToB = id('copy-a-to-b');
    this.el.copyBToA = id('copy-b-to-a');
    this.el.floatingPuck = id('floating-puck');

    this.el.rootPathOverlay = id('root-path-overlay');
    this.el.rootPathInput = id('root-path-input');
    this.el.rootPathSaveBtn = id('root-path-save-btn');
    this.el.rootPathCancelBtn = id('root-path-cancel-btn');
    this.el.rootPathClearBtn = id('root-path-clear-btn');

    this.el.confirmOverlay = id('confirm-overlay');
    this.el.confirmTitle = id('confirm-title');
    this.el.confirmMessage = id('confirm-message');
    this.el.confirmCancelBtn = id('confirm-cancel-btn');
    this.el.confirmOkBtn = id('confirm-ok-btn');

    this.el.toast = id('toast');
  },

  bindEvents() {
    this.el.chooseFolderBtn.addEventListener('click', () => this.handleChooseFolder());
    this.el.emptyChooseFolderBtn.addEventListener('click', () => this.handleChooseFolder());
    this.el.reconnectBtn.addEventListener('click', () => this.handleReconnect());
    this.el.rescanBtn.addEventListener('click', () => this.handleRescan());

    this.el.filterInput.addEventListener('input', () => {
      this.filterText = this.el.filterInput.value;
      this.renderBoard();
    });
    this.el.sortSelect.addEventListener('change', () => {
      this.sortMode = this.el.sortSelect.value;
      this.renderBoard();
    });

    // Selection bar
    this.el.selectionSwapBtn.addEventListener('click', () => this.swapSelection());
    this.el.selectionClearBtn.addEventListener('click', () => this.clearSelection());

    // Sidebar: swap mirrors the selection bar; minimize only (no close in v3); puck re-opens.
    this.el.sidebarSwapBtn.addEventListener('click', () => this.swapSelection());
    this.el.sidebarMinimizeBtn.addEventListener('click', () => this.minimizeSidebar());
    this.el.floatingPuck.addEventListener('click', () => this.openSidebar());

    this.el.copyAToB.addEventListener('click', () => this.handleCopy('A', 'B'));
    this.el.copyBToA.addEventListener('click', () => this.handleCopy('B', 'A'));

    // Root-path modal
    this.el.rootPathBtn.addEventListener('click', () => this.openRootPathModal());
    this.el.rootPathSaveBtn.addEventListener('click', () => this.saveRootPath());
    this.el.rootPathCancelBtn.addEventListener('click', () => this.closeRootPathModal());
    this.el.rootPathClearBtn.addEventListener('click', () => this.clearRootPath());
    this.el.rootPathOverlay.addEventListener('click', (e) => {
      if (e.target === this.el.rootPathOverlay) this.closeRootPathModal();
    });

    // Clicking empty space (anywhere outside a repo card) clears the visual focus.
    // Card clicks land on a `.repo-card`, so closest() finds one and we skip deselect.
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.repo-card')) this.deselectCard();
    });

    // Confirm modal
    this.el.confirmCancelBtn.addEventListener('click', () => this.closeConfirmModal());
    this.el.confirmOverlay.addEventListener('click', (e) => {
      if (e.target === this.el.confirmOverlay) this.closeConfirmModal();
    });
  },

  /* ---- Folder access / reopen flow ---- */

  async tryReopen() {
    let handle;
    try { handle = await window.Vantage.Persist.loadHandle(); } catch (err) { handle = null; }
    if (!handle) { this.showEmptyState(); return; }

    let permission;
    try { permission = await handle.queryPermission({ mode: 'readwrite' }); }
    catch (err) { await window.Vantage.Persist.saveHandle(null); this.showEmptyState(); return; }

    if (permission === 'granted') {
      this.rootHandle = handle;
      await this.loadFromCacheThenScan();
    } else {
      this.rootHandle = handle;
      this.showReconnectPrompt();
      await this.loadFromCacheOnly();
    }
  },

  async loadFromCacheOnly() {
    let cache;
    try { cache = await window.Vantage.Persist.loadCache(); } catch (err) { cache = null; }
    if (cache && Array.isArray(cache.repos) && cache.repos.length > 0) {
      this.repos = cache.repos.map((r) => ({
        name: r.name,
        dirHandle: null,
        stack: r.stack || [],
        lastActivity: r.lastActivity != null ? r.lastActivity : null,
        fileTree: null,
      }));
      this.showBoard();
      this.renderBoard();
    } else {
      this.showEmptyState();
    }
  },

  async loadFromCacheThenScan() {
    await this.loadFromCacheOnly();
    await this.handleRescan();
  },

  async handleChooseFolder() {
    let result;
    try { result = await window.Vantage.Scanner.chooseRoot(); }
    catch (err) { this.showNotice('Could not open folder: ' + (err.message || err)); return; }
    if (!result) return; // cancelled

    this.rootHandle = result.handle;
    this.repos = result.repos;
    this.el.reconnectBtn.hidden = true;
    this.showBoard();
    this.renderBoard();
    this.clearNotice();
  },

  async handleReconnect() {
    if (!this.rootHandle) return;
    let permission;
    try { permission = await this.rootHandle.requestPermission({ mode: 'readwrite' }); }
    catch (err) { this.showNotice('Could not request permission: ' + err.message); return; }

    if (permission === 'granted') {
      this.el.reconnectBtn.hidden = true;
      await this.handleRescan();
    } else {
      this.showNotice('Permission was not granted. Folder access is read-only or unavailable.');
    }
  },

  async handleRescan() {
    if (!this.rootHandle) return;
    this.el.rescanBtn.disabled = true;
    try {
      this.repos = await window.Vantage.Scanner.scanRoot(this.rootHandle);
      this.showBoard();
      this.renderBoard();
      this.clearNotice();
    } catch (err) {
      console.error('scanRoot failed:', err);
      await window.Vantage.Persist.saveHandle(null);
      this.rootHandle = null;
      this.showNotice('Scan failed: ' + (err && err.message ? err.message : err));
      this.showEmptyState();
    } finally {
      this.el.rescanBtn.disabled = false;
    }
  },

  /* ---- View toggles ---- */

  showEmptyState() {
    this.el.emptyState.hidden = false;
    this.el.board.hidden = true;
    this.el.rescanBtn.hidden = true;
  },

  showBoard() {
    this.el.emptyState.hidden = true;
    this.el.board.hidden = false;
    this.el.rescanBtn.hidden = false;
  },

  showReconnectPrompt() { this.el.reconnectBtn.hidden = false; },

  /* ---- Notices / toasts ---- */

  showNotice(message) {
    this.el.noticeBar.textContent = '';
    const span = document.createElement('span');
    span.textContent = message;
    const dismiss = document.createElement('button');
    dismiss.className = 'notice-dismiss';
    dismiss.textContent = '×';
    dismiss.addEventListener('click', () => this.clearNotice());
    this.el.noticeBar.appendChild(span);
    this.el.noticeBar.appendChild(dismiss);
    this.el.noticeBar.hidden = false;
  },

  clearNotice() { this.el.noticeBar.hidden = true; this.el.noticeBar.textContent = ''; },

  showToast(message, isError) {
    this.el.toast.textContent = message;
    this.el.toast.classList.toggle('toast-error', !!isError);
    this.el.toast.hidden = false;
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => { this.el.toast.hidden = true; }, 2600);
  },

  /* ---- Formatting helpers ---- */

  formatRelativeTime(epochMs) {
    if (epochMs == null) return '—';
    const diffSec = Math.floor((Date.now() - epochMs) / 1000);
    if (diffSec < 60) return 'just now';
    const diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return diffMin + 'm ago';
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return diffHr + 'h ago';
    const diffDay = Math.floor(diffHr / 24);
    if (diffDay < 30) return diffDay + 'd ago';
    const diffMonth = Math.floor(diffDay / 30);
    if (diffMonth < 12) return diffMonth + 'mo ago';
    return Math.floor(diffDay / 365) + 'y ago';
  },

  /* ---- Board rendering ---- */

  getFilteredSortedRepos() {
    const filterLower = this.filterText.trim().toLowerCase();
    const list = this.repos.filter((r) =>
      filterLower === '' || r.name.toLowerCase().includes(filterLower));

    const byActivity = (a, b) => {
      const at = a.lastActivity == null ? -Infinity : a.lastActivity;
      const bt = b.lastActivity == null ? -Infinity : b.lastActivity;
      return bt - at;
    };

    if (this.sortMode === 'alphabetical') {
      return list.slice().sort((a, b) => a.name.localeCompare(b.name));
    }
    if (this.sortMode === 'stack') {
      // Group under the primary (first) badge; no-stack repos under "Other".
      return list.slice().sort((a, b) => {
        const ag = (a.stack && a.stack[0]) || '~Other';
        const bg = (b.stack && b.stack[0]) || '~Other';
        if (ag !== bg) return ag.localeCompare(bg);
        return byActivity(a, b);
      });
    }
    return list.slice().sort(byActivity); // 'last-activity' (default)
  },

  renderBoard() {
    const board = this.el.board;
    board.textContent = '';
    board.classList.remove('empty');

    const list = this.getFilteredSortedRepos();
    if (list.length === 0) { board.classList.add('empty'); return; }

    for (const repo of list) board.appendChild(this.buildRepoCard(repo));
  },

  // Pure derivation of the highlight classes for a repo (no stored state).
  highlightFor(repo) {
    return {
      isCompareA: !!(this.selection.sideA && this.selection.sideA.repoName === repo.name),
      isCompareB: !!(this.selection.sideB && this.selection.sideB.repoName === repo.name),
      isActive: this.activeRepoName === repo.name,
    };
  },

  buildRepoCard(repo) {
    const card = document.createElement('div');
    card.className = 'repo-card';
    card.dataset.repoName = repo.name;
    const isExpanded = !!repo._expanded;
    if (isExpanded) card.classList.add('expanded');

    // Click anywhere on the card selects it (visual focus only). Interactive
    // children (chevron, file rows, action buttons) stopPropagation below so
    // they keep their own behaviour without also re-selecting.
    card.addEventListener('click', () => this.selectCard(repo));

    // Derived highlight states (v3).
    const hl = this.highlightFor(repo);
    if (hl.isCompareA) card.classList.add('is-compare-a');
    if (hl.isCompareB) card.classList.add('is-compare-b');
    if (hl.isActive) card.classList.add('is-active');

    // Header
    const header = document.createElement('div');
    header.className = 'repo-card-header';
    const headline = document.createElement('div');
    headline.className = 'repo-card-headline';
    const name = document.createElement('div');
    name.className = 'repo-card-name';
    name.textContent = repo.name;
    headline.appendChild(name);
    if (hl.isCompareA) headline.appendChild(this.buildCompareBadge('A'));
    if (hl.isCompareB) headline.appendChild(this.buildCompareBadge('B'));

    const toggle = document.createElement('div');
    toggle.className = 'repo-card-toggle';
    toggle.textContent = '▸';
    header.appendChild(headline);
    header.appendChild(toggle);
    // The chevron expands/collapses and also selects the card (force on, not toggle).
    toggle.addEventListener('click', (e) => {
      e.stopPropagation();
      this.activeRepoName = repo.name;
      this.toggleCardExpanded(repo);
    });
    card.appendChild(header);

    // Meta
    const meta = document.createElement('div');
    meta.className = 'repo-card-meta';
    const badges = document.createElement('div');
    badges.className = 'stack-badges';
    for (const label of repo.stack || []) {
      const badge = document.createElement('span');
      badge.className = 'badge badge-secondary';
      badge.textContent = label;
      badges.appendChild(badge);
    }
    const activity = document.createElement('div');
    activity.className = 'last-activity';
    activity.textContent = this.formatRelativeTime(repo.lastActivity);
    meta.appendChild(badges);
    meta.appendChild(activity);
    card.appendChild(meta);

    // Expanded body: VSCode action + file tree
    if (isExpanded) {
      const body = document.createElement('div');
      body.className = 'expanded-body';

      const actions = document.createElement('div');
      actions.className = 'expanded-actions';
      actions.addEventListener('click', (e) => e.stopPropagation());
      actions.appendChild(this.buildVscodeButton(repo));
      body.appendChild(actions);

      const treeContainer = document.createElement('div');
      treeContainer.className = 'file-tree-container';
      body.appendChild(treeContainer);
      card.appendChild(body);

      this.renderFileTreeInto(repo, treeContainer);
    }

    return card;
  },

  buildCompareBadge(side) {
    const b = document.createElement('span');
    b.className = 'compare-badge ' + (side === 'A' ? 'badge-a' : 'badge-b');
    b.textContent = side;
    b.title = side === 'A' ? 'Contributes Side A' : 'Contributes Side B';
    return b;
  },

  buildVscodeButton(repo) {
    const uri = window.Vantage.Editor.vscodeUri(repo.name);
    if (uri) {
      const a = document.createElement('a');
      a.className = 'btn btn-outline btn-sm';
      a.textContent = 'Open in VSCode';
      a.href = uri;
      a.title = 'Open ' + repo.name + ' in VSCode';
      return a;
    }
    const btn = document.createElement('button');
    btn.className = 'btn btn-outline btn-sm';
    btn.textContent = 'Open in VSCode';
    btn.disabled = true;
    btn.title = 'Set root path to enable';
    return btn;
  },

  toggleCardExpanded(repo) {
    repo._expanded = !repo._expanded;
    this.renderBoard();
  },

  // Selecting a card is visual focus only (the .is-active highlight); it is
  // independent of expand state and never touches the A/B file comparison.
  // Clicking the already-selected card toggles it back off.
  selectCard(repo) {
    this.activeRepoName = this.activeRepoName === repo.name ? null : repo.name;
    this.renderBoard();
  },

  deselectCard() {
    if (this.activeRepoName == null) return;
    this.activeRepoName = null;
    this.renderBoard();
  },

  /* ---- File tree rendering ---- */

  async renderFileTreeInto(repo, container) {
    if (repo.fileTree) { this.renderTreeNode(repo, repo.fileTree, container, true); return; }

    if (!repo.dirHandle) {
      const err = document.createElement('div');
      err.className = 'file-tree-error';
      err.textContent = 'No folder handle available — rescan to enable file browsing.';
      container.appendChild(err);
      return;
    }

    const spinner = document.createElement('div');
    spinner.className = 'file-tree-spinner';
    spinner.textContent = 'Loading…';
    container.appendChild(spinner);

    try {
      const tree = await window.Vantage.Scanner.readTree(repo);
      if (!container.isConnected) return;
      container.textContent = '';
      this.renderTreeNode(repo, tree, container, true);
    } catch (err) {
      container.textContent = '';
      const errEl = document.createElement('div');
      errEl.className = 'file-tree-error';
      errEl.textContent = 'Could not read this repo’s files (folder may have changed). Try Rescan.';
      container.appendChild(errEl);
      this.showNotice('Could not read “' + repo.name + '”. The folder may have changed — try Rescan.');
    }
  },

  renderTreeNode(repo, node, container, isRoot) {
    const ul = document.createElement('ul');
    ul.className = isRoot ? 'tree-node tree-root' : 'tree-node';

    for (const child of node.children || []) {
      const li = document.createElement('li');

      if (child.kind === 'dir') {
        const row = document.createElement('div');
        row.className = 'tree-row tree-dir';
        const icon = document.createElement('span');
        icon.className = 'tree-row-icon';
        icon.textContent = child._open ? '▾' : '▸';
        const nameEl = document.createElement('span');
        nameEl.className = 'tree-row-name';
        nameEl.textContent = child.name;
        row.appendChild(icon);
        row.appendChild(nameEl);
        li.appendChild(row);

        const childrenContainer = document.createElement('div');
        childrenContainer.className = 'tree-children';
        if (!child._open) childrenContainer.classList.add('collapsed');
        li.appendChild(childrenContainer);

        row.addEventListener('click', async (e) => {
          e.stopPropagation();
          child._open = !child._open;
          icon.textContent = child._open ? '▾' : '▸';
          if (child._open) {
            childrenContainer.classList.remove('collapsed');
            if (child.children === null) {
              const spinner = document.createElement('div');
              spinner.className = 'file-tree-spinner';
              spinner.textContent = 'Loading…';
              childrenContainer.appendChild(spinner);
              try {
                await window.Vantage.Scanner.readChildren(child);
                childrenContainer.textContent = '';
                this.renderTreeNode(repo, child, childrenContainer, false);
              } catch (err) {
                childrenContainer.textContent = '';
                const errEl = document.createElement('div');
                errEl.className = 'file-tree-error';
                errEl.textContent = 'Could not read this folder.';
                childrenContainer.appendChild(errEl);
              }
            } else if (childrenContainer.children.length === 0) {
              this.renderTreeNode(repo, child, childrenContainer, false);
            }
          } else {
            childrenContainer.classList.add('collapsed');
          }
        });
      } else {
        // file
        const row = document.createElement('div');
        row.className = 'tree-row tree-file';
        const path = this.buildChildPath(node, child);

        const isA = this.selection.sideA && this.selection.sideA.repoName === repo.name && this.selection.sideA.path === path;
        const isB = this.selection.sideB && this.selection.sideB.repoName === repo.name && this.selection.sideB.path === path;
        if (isA || isB) row.classList.add('assigned');

        const icon = document.createElement('span');
        icon.className = 'tree-row-icon';
        icon.textContent = '•';
        const nameEl = document.createElement('span');
        nameEl.className = 'tree-row-name';
        nameEl.textContent = child.name;

        const actions = document.createElement('span');
        actions.className = 'tree-row-actions';
        const btnA = document.createElement('button');
        btnA.className = 'btn'; btnA.textContent = 'A'; btnA.title = 'Assign to Side A';
        if (isA) btnA.classList.add('active-a');
        btnA.addEventListener('click', (e) => { e.stopPropagation(); this.assignToSide('A', repo, path, child.handle); });
        const btnB = document.createElement('button');
        btnB.className = 'btn'; btnB.textContent = 'B'; btnB.title = 'Assign to Side B';
        if (isB) btnB.classList.add('active-b');
        btnB.addEventListener('click', (e) => { e.stopPropagation(); this.assignToSide('B', repo, path, child.handle); });
        actions.appendChild(btnA);
        actions.appendChild(btnB);

        row.appendChild(icon);
        row.appendChild(nameEl);
        row.appendChild(actions);
        row.addEventListener('click', (e) => { e.stopPropagation(); this.assignToSide(this.computeNextSide(), repo, path, child.handle); });
        li.appendChild(row);
      }
      ul.appendChild(li);
    }
    container.appendChild(ul);
  },

  buildChildPath(parent, child) {
    const parentPath = parent._path || '';
    const path = parentPath ? parentPath + '/' + child.name : child.name;
    child._path = path;
    return path;
  },

  /* ---- Selection ---- */

  // Which side a plain row-click will fill: first empty side, else rotate.
  computeNextSide() {
    if (!this.selection.sideA) return 'A';
    if (!this.selection.sideB) return 'B';
    return this.nextSide;
  },

  assignToSide(side, repo, path, handle) {
    const entry = { repoName: repo.name, path, handle };
    if (side === 'A') { this.selection.sideA = entry; this.nextSide = 'B'; }
    else { this.selection.sideB = entry; this.nextSide = 'A'; }
    this.renderBoard();
    this.renderSelectionBar();
    this.onSelectionChanged();
  },

  swapSelection() {
    const a = this.selection.sideA;
    this.selection.sideA = this.selection.sideB;
    this.selection.sideB = a;
    this.lastDiff = null; // direction flipped — invalidate the cached diff
    this.renderBoard();
    this.renderSelectionBar();
    // Swap is not a new file pick: preserve the current sidebar mode (don't
    // re-open a minimized panel). Only recompute the diff if it's already visible;
    // a minimized panel recomputes lazily on reopen (lastDiff is null).
    this.renderSidebar();
    if (this.selection.sideA && this.selection.sideB && this.sidebarMode === 'open') {
      this.runDiffAndRender();
    }
  },

  clearSelection() {
    this.selection.sideA = null;
    this.selection.sideB = null;
    this.nextSide = 'A';
    this.lastDiff = null;
    this.sidebarMode = 'open'; // reset default; nothing shows until both sides set again
    this.renderBoard();
    this.renderSelectionBar();
    this.renderSidebar();
  },

  // Called whenever a file pick changes the selection.
  onSelectionChanged() {
    const { sideA, sideB } = this.selection;
    if (sideA && sideB) {
      // A different file pick invalidates the cached diff and (re)opens.
      this.lastDiff = null;
      this.sidebarMode = 'open';
      this.renderSidebar();
      this.runDiffAndRender();
    } else {
      // Fewer than two sides — neither panel nor puck shows.
      this.renderSidebar();
    }
  },

  /* ---- Selection bar (bridge to the diff sidebar) ---- */

  renderSelectionBar() {
    const { sideA, sideB } = this.selection;
    const anySet = !!(sideA || sideB);
    this.el.selectionBar.hidden = !anySet;
    if (!anySet) return;

    this.el.selectionSlots.textContent = '';
    this.el.selectionSlots.appendChild(this.buildSelectionSlot('A', sideA));
    this.el.selectionSlots.appendChild(this.buildSelectionSlot('B', sideB));

    const next = this.computeNextSide();
    this.el.selectionNext.innerHTML = '';
    const label = document.createElement('span');
    label.textContent = 'next pick → ';
    const strong = document.createElement('strong');
    strong.textContent = next;
    this.el.selectionNext.appendChild(label);
    this.el.selectionNext.appendChild(strong);

    this.el.selectionSwapBtn.disabled = !(sideA && sideB);
  },

  buildSelectionSlot(side, entry) {
    const slot = document.createElement('span');
    slot.className = 'selection-slot ' + (side === 'A' ? 'slot-a' : 'slot-b');
    const label = document.createElement('span');
    label.className = 'slot-label';
    label.textContent = side;
    slot.appendChild(label);
    const value = document.createElement('span');
    value.className = 'slot-value';
    if (entry) {
      value.textContent = entry.repoName + '/' + entry.path;
    } else {
      slot.classList.add('slot-empty');
      value.textContent = 'not set';
    }
    slot.appendChild(value);
    return slot;
  },

  /* ---- Diff sidebar (modes: open | minimized — never closed) ---- */

  openSidebar() {
    if (!this.selection.sideA || !this.selection.sideB) return;
    this.sidebarMode = 'open';
    this.renderSidebar();
    if (!this.lastDiff) this.runDiffAndRender();
  },

  minimizeSidebar() {
    this.sidebarMode = 'minimized';
    this.renderSidebar();
  },

  // Reconcile panel position, puck visibility, and side labels from state.
  renderSidebar() {
    const { sideA, sideB } = this.selection;
    const bothSet = !!(sideA && sideB);

    this.el.sidebar.classList.toggle('open', this.sidebarMode === 'open' && bothSet);
    this.el.floatingPuck.hidden = !(this.sidebarMode === 'minimized' && bothSet);

    if (bothSet) {
      this.el.sidebarSides.innerHTML = '';
      const a = document.createElement('div');
      a.className = 'side-a';
      a.textContent = 'A · ' + sideA.repoName + '/' + sideA.path;
      const b = document.createElement('div');
      b.className = 'side-b';
      b.textContent = 'B · ' + sideB.repoName + '/' + sideB.path;
      this.el.sidebarSides.appendChild(a);
      this.el.sidebarSides.appendChild(b);
    } else {
      this.el.sidebarSides.textContent = '';
    }
  },

  setDiffStatus(text, cls) {
    this.el.diffStatus.hidden = false;
    this.el.diffStatus.className = 'diff-status' + (cls ? ' ' + cls : '');
    this.el.diffStatus.textContent = text;
  },

  async runDiffAndRender() {
    const { sideA, sideB } = this.selection;
    if (!sideA || !sideB) return;

    this.el.diffStatus.hidden = true;
    this.el.diffStatus.className = 'diff-status';
    this.el.diffView.textContent = '';
    this.el.sidebarFooter.hidden = true;

    let bufA, bufB;
    try {
      bufA = await (await sideA.handle.getFile()).arrayBuffer();
      bufB = await (await sideB.handle.getFile()).arrayBuffer();
    } catch (err) {
      this.setDiffStatus('Could not read one or both files (folder may have changed). Try Rescan.', 'diff-error');
      return;
    }

    const Compare = window.Vantage.Compare;
    if (Compare.looksBinary(bufA) || Compare.looksBinary(bufB)) {
      this.setDiffStatus("Binary file — can't compare.", 'diff-binary');
      this.lastDiff = this.diffKey();
      this.el.sidebarFooter.hidden = false;
      this.updateCopyBarLabels();
      return;
    }

    const decoder = new TextDecoder('utf-8');
    const textA = decoder.decode(bufA);
    const textB = decoder.decode(bufB);

    if (textA === textB) {
      this.setDiffStatus('Files are identical.', 'diff-identical');
      this.lastDiff = this.diffKey();
      this.el.sidebarFooter.hidden = false;
      this.updateCopyBarLabels();
      return;
    }

    const lines = Compare.diff(textA, textB);
    this.renderDiffView(lines);
    // Cache keyed to the current A/B pair so minimize → reopen is instant.
    this.lastDiff = Object.assign(this.diffKey(), { lines });
    this.el.sidebarFooter.hidden = false;
    this.updateCopyBarLabels();
  },

  // Identity of the current A/B handle pair, for cache invalidation.
  diffKey() {
    const { sideA, sideB } = this.selection;
    return {
      keyA: sideA ? sideA.repoName + '/' + sideA.path : null,
      keyB: sideB ? sideB.repoName + '/' + sideB.path : null,
    };
  },

  renderDiffView(lines) {
    const frag = document.createDocumentFragment();
    for (const line of lines) {
      const row = document.createElement('div');
      row.className = 'diff-line diff-' + line.kind;
      const gutter = document.createElement('span');
      gutter.className = 'diff-gutter';
      gutter.textContent = line.kind === 'add' ? '+' : line.kind === 'del' ? '-' : '';
      const text = document.createElement('span');
      text.className = 'diff-text';
      text.textContent = line.text;
      row.appendChild(gutter);
      row.appendChild(text);
      frag.appendChild(row);
    }
    this.el.diffView.appendChild(frag);
  },

  updateCopyBarLabels() {
    const { sideA, sideB } = this.selection;
    if (!sideA || !sideB) return;
    this.el.copyAToB.textContent = 'Copy A → B  (overwrite ' + sideB.repoName + '/' + sideB.path + ')';
    this.el.copyBToA.textContent = 'Copy B → A  (overwrite ' + sideA.repoName + '/' + sideA.path + ')';
  },

  /* ---- Copy / overwrite ---- */

  async handleCopy(fromSide, toSide) {
    const src = fromSide === 'A' ? this.selection.sideA : this.selection.sideB;
    const dst = toSide === 'A' ? this.selection.sideA : this.selection.sideB;
    if (!src || !dst) return;

    const dstRepo = this.repos.find((r) => r.name === dst.repoName);
    if (!dstRepo || !dstRepo.dirHandle) {
      this.showToast('Destination repo handle unavailable. Try Rescan.', true);
      return;
    }

    if (this.rootHandle) {
      try {
        const perm = await this.rootHandle.queryPermission({ mode: 'readwrite' });
        if (perm !== 'granted') {
          const req = await this.rootHandle.requestPermission({ mode: 'readwrite' });
          if (req !== 'granted') { this.showToast('Write permission denied.', true); return; }
        }
      } catch (err) { /* proceed; the write will fail if truly unauthorized */ }
    }

    const Copy = window.Vantage.Copy;
    const pathParts = dst.path.split('/');
    const fileName = pathParts[pathParts.length - 1];

    let destDir;
    try { destDir = await Copy.resolveDestDir(dstRepo.dirHandle, pathParts); }
    catch (err) { this.showToast('Could not resolve destination folder. Try Rescan.', true); return; }

    let exists;
    try { exists = await Copy.destExists(destDir, fileName); } catch (err) { exists = false; }

    const targetPath = dst.repoName + '/' + dst.path;

    if (exists) {
      const confirmed = await this.showConfirmModal(
        'Confirm overwrite',
        'This will overwrite "' + targetPath + '" with the contents of "' +
          src.repoName + '/' + src.path + '". This cannot be undone.'
      );
      if (!confirmed) return;
    }

    try { await Copy.copyFile(src.handle, destDir, fileName); }
    catch (err) {
      this.showToast('Write failed: ' + (err.message || err) + '. The folder may have changed — try Rescan.', true);
      return;
    }

    try { dst.handle = await destDir.getFileHandle(fileName); } catch (err) { /* ignore */ }

    // Re-read the target and refresh the diff so the files now show as matching.
    this.lastDiff = null;
    await this.runDiffAndRender();
    this.showToast('Copied to ' + targetPath);
  },

  /* ---- Confirm modal ---- */

  showConfirmModal(title, message) {
    this.el.confirmTitle.textContent = title;
    this.el.confirmMessage.textContent = message;
    this.el.confirmOverlay.hidden = false;

    return new Promise((resolve) => {
      const onOk = () => { cleanup(); resolve(true); };
      const onCancel = () => { cleanup(); resolve(false); };
      const cleanup = () => {
        this.el.confirmOkBtn.removeEventListener('click', onOk);
        this.el.confirmCancelBtn.removeEventListener('click', onCancel);
        this.el.confirmOverlay.hidden = true;
        this._confirmResolveOnOverlayClose = null;
      };
      this.el.confirmOkBtn.addEventListener('click', onOk);
      this.el.confirmCancelBtn.addEventListener('click', onCancel);
      this._confirmResolveOnOverlayClose = onCancel;
    });
  },

  closeConfirmModal() {
    if (this._confirmResolveOnOverlayClose) this._confirmResolveOnOverlayClose();
  },

  /* ---- Root-path modal ---- */

  openRootPathModal() {
    this.el.rootPathInput.value = this.rootPath || '';
    this.el.rootPathOverlay.hidden = false;
    setTimeout(() => this.el.rootPathInput.focus(), 0);
  },

  closeRootPathModal() { this.el.rootPathOverlay.hidden = true; },

  async saveRootPath() {
    const value = this.el.rootPathInput.value.trim();
    this.rootPath = value === '' ? null : value;
    window.Vantage.Editor.setRootPath(this.rootPath);
    try { await window.Vantage.Persist.saveRootPath(this.rootPath); }
    catch (err) { this.showToast('Could not save root path: ' + (err.message || err), true); }
    this.closeRootPathModal();
    this.renderBoard(); // re-enable any visible VSCode buttons
    this.showToast(this.rootPath ? 'Root path saved.' : 'Root path cleared.');
  },

  async clearRootPath() {
    this.rootPath = null;
    window.Vantage.Editor.setRootPath(null);
    this.el.rootPathInput.value = '';
    try { await window.Vantage.Persist.saveRootPath(null); } catch (err) { /* ignore */ }
    this.closeRootPathModal();
    this.renderBoard();
    this.showToast('Root path cleared.');
  },
};
