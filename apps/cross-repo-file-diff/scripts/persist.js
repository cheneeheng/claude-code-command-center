/* ===================================================================
   Vantage.Persist — IndexedDB: directory handle, scan cache, root path
   Store: object store 'vantage' in DB 'vantage'.
   =================================================================== */

'use strict';

window.Vantage.Persist = {
  DB_NAME: 'vantage',
  DB_VERSION: 1,
  STORE: 'vantage',
  HANDLE_KEY: 'rootHandle',
  CACHE_KEY: 'scanCache',
  ROOT_PATH_KEY: 'rootPath',

  _dbPromise: null,

  _openDb() {
    if (this._dbPromise) return this._dbPromise;
    const self = this;
    this._dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(self.DB_NAME, self.DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(self.STORE)) db.createObjectStore(self.STORE);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    return this._dbPromise;
  },

  async _get(key) {
    const db = await this._openDb();
    const store = this.STORE;
    return new Promise((resolve, reject) => {
      const tx = db.transaction(store, 'readonly');
      const req = tx.objectStore(store).get(key);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  },

  async _set(key, value) {
    const db = await this._openDb();
    const store = this.STORE;
    return new Promise((resolve, reject) => {
      const tx = db.transaction(store, 'readwrite');
      const req = tx.objectStore(store).put(value, key);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  },

  async saveHandle(handle) { return this._set(this.HANDLE_KEY, handle); },
  async loadHandle() { return this._get(this.HANDLE_KEY); },

  // cache = { scannedAt, repos: [{ name, stack, lastActivity }] } — live handles are never serialised.
  async saveCache(cache) { return this._set(this.CACHE_KEY, cache); },
  async loadCache() { return this._get(this.CACHE_KEY); },

  // Optional absolute root path, used only to build VSCode links (ITER_04).
  async saveRootPath(str) { return this._set(this.ROOT_PATH_KEY, str); },
  async loadRootPath() {
    const v = await this._get(this.ROOT_PATH_KEY);
    return v == null ? null : v;
  },
};
