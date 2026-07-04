// ── View state ───────────────────────────────────────────────────────────────
// Single source of truth, mirrored to the URL (the shareable form). `range` and
// `project` are server-scoped (refetch); `model`/`day`/`q` filter already-loaded
// rows client-side. Device prefs (range, page size, theme, timeout) persist in
// localStorage; drill-down state lives only in the URL.
let filterProject = null;  // server-scoped
let filterModel = null;    // client display filter (matched by model family)
let filterDay = null;      // client display filter (local YYYY-MM-DD)
let searchQuery = '';       // client search over session id + project

const RANGE_KEY = 'cc_range';
const RANGES = ['7d', '30d', '90d', '12m', 'all'];

function getRange() {
  const v = localStorage.getItem(RANGE_KEY) || 'all';
  return RANGES.includes(v) ? v : 'all';
}

function onRangeChange(r) {
  if (!RANGES.includes(r) || r === getRange()) return;
  localStorage.setItem(RANGE_KEY, r);
  sessionPage = 1;
  writeStateToURL();
  fetchData().then(startCountdown);
}

// ── Drill-down setters ─────────────────────────────────────────────────────────
// Server-scoped changes refetch; client filters re-render from the loaded data.
function setProject(p) {
  filterProject = p || null;
  sessionPage = 1;
  writeStateToURL();
  fetchData().then(startCountdown);
}
function clearProject() { setProject(null); }

function setModel(m) { _setClient(() => { filterModel = m || null; }); }
function clearModel() { _setClient(() => { filterModel = null; }); }

function setDay(d) { _setClient(() => { filterDay = d || null; }); }
function clearDay() { _setClient(() => { filterDay = null; }); }

function setSearchTo(q) { _setClient(() => { searchQuery = (q || '').trim(); }); }
function clearSearch() { _setClient(() => { searchQuery = ''; }); }

function _setClient(mutate) {
  mutate();
  sessionPage = 1;
  writeStateToURL();
  if (lastData) render(lastData);
}

// Debounced search box (250ms); refocuses itself after the re-render.
let _searchTimer = null;
function onSearchInput(el) {
  clearTimeout(_searchTimer);
  const v = el.value;
  _searchTimer = setTimeout(() => {
    searchQuery = v.trim();
    sessionPage = 1;
    writeStateToURL();
    refocusSearch = true;
    if (lastData) render(lastData);
  }, 250);
}

// ── URL state (shareable) ──────────────────────────────────────────────────────
function writeStateToURL() {
  const p = new URLSearchParams();
  const range = getRange();
  if (range !== 'all') p.set('range', range);
  if (filterProject) p.set('project', filterProject);
  if (filterModel) p.set('model', filterModel);
  if (filterDay) p.set('day', filterDay);
  if (searchQuery) p.set('q', searchQuery);
  if (sessionSort.key !== 'last_ts') p.set('sort', sessionSort.key);
  if (sessionSort.dir !== 'desc') p.set('dir', sessionSort.dir);
  if (sessionPage > 1) p.set('page', String(sessionPage));
  const qs = p.toString();
  history.replaceState(null, '', qs ? '?' + qs : location.pathname);
}

function readStateFromURL() {
  const p = new URLSearchParams(location.search);
  if (RANGES.includes(p.get('range'))) localStorage.setItem(RANGE_KEY, p.get('range'));
  filterProject = p.get('project') || null;
  filterModel = p.get('model') || null;
  filterDay = p.get('day') || null;
  searchQuery = p.get('q') || '';
  if (p.get('sort')) sessionSort.key = p.get('sort');
  if (p.get('dir')) sessionSort.dir = p.get('dir') === 'asc' ? 'asc' : 'desc';
  const page = parseInt(p.get('page') || '1');
  if (page > 0) sessionPage = page;
}

// ── Session lookback ───────────────────────────────────────────────────────────
function getSessionLookback() {
  const v = parseInt(localStorage.getItem('cc_session_lookback') || '0');
  return isNaN(v) || v < 0 ? 0 : v;
}

function onLookbackChange(el) {
  const v = el.value.trim();
  localStorage.setItem('cc_session_lookback', v === '' ? '0' : String(Math.max(0, parseInt(v) || 0)));
  sessionPage = 1;
  fetchData().then(startCountdown);
}

// ── Recent sessions pagination ─────────────────────────────────────────────────
let lastData = null;
let sessionPage = 1;
let refocusSearch = false;  // set by onSearchInput so render() restores focus

function getSessionPageSize() {
  const v = parseInt(localStorage.getItem('cc_session_page_size') || '25');
  return isNaN(v) || v <= 0 ? 25 : v;
}

function onPageSizeChange(el) {
  localStorage.setItem('cc_session_page_size', String(Math.max(1, parseInt(el.value) || 25)));
  sessionPage = 1;
  if (lastData) render(lastData);
}

function onPageChange(page) {
  sessionPage = Math.max(1, page);
  writeStateToURL();
  if (lastData) render(lastData);
}

// ── Session table sort ─────────────────────────────────────────────────────────
let sessionSort = { key: 'last_ts', dir: 'desc' };
// Columns that read most naturally largest/newest-first on the first click.
const DESC_FIRST_KEYS = ['total_tokens', 'input_tokens', 'output_tokens', 'cost_usd',
  'duration_secs', 'cost_per_hour', 'cache_hit_pct', 'last_ts'];

function onSortChange(key) {
  if (sessionSort.key === key) {
    sessionSort.dir = sessionSort.dir === 'asc' ? 'desc' : 'asc';
  } else {
    sessionSort = { key, dir: DESC_FIRST_KEYS.includes(key) ? 'desc' : 'asc' };
  }
  sessionPage = 1;
  writeStateToURL();
  if (lastData) render(lastData);
}

// ── Live timeout setting ───────────────────────────────────────────────────────
const TIMEOUT_KEY = 'cc_live_timeout_min';

function getTimeoutSecs() {
  const el = document.getElementById('live-timeout');
  const v = el ? parseFloat(el.value) : parseFloat(localStorage.getItem(TIMEOUT_KEY) || '30');
  return isNaN(v) || v <= 0 ? 1800 : Math.round(v * 60);
}

function onTimeoutChange(el) {
  localStorage.setItem(TIMEOUT_KEY, el.value);
  fetchData().then(startCountdown);
}
