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
