// ── Fetch & refresh loop ───────────────────────────────────────────────────────
let countdown = 60;
let timer;

async function fetchData() {
  document.getElementById('spinner').classList.add('active');
  try {
    let url = '/api/data?live_timeout=' + getTimeoutSecs() + '&range=' + getRange();
    if (filterProject) url += '&project=' + encodeURIComponent(filterProject);
    const res = await fetch(url);
    if (!res.ok) throw new Error('fetch failed');
    const data = await res.json();
    render(data);
    const now = new Date();
    document.getElementById('last-updated').textContent =
      'updated ' + now.toLocaleTimeString(undefined, {hour:'2-digit',minute:'2-digit',second:'2-digit'});
  } catch (e) {
    console.error('fetch error', e);
  } finally {
    document.getElementById('spinner').classList.remove('active');
  }
}

function startCountdown() {
  clearInterval(timer);
  countdown = 60;
  timer = setInterval(() => {
    countdown--;
    document.getElementById('refresh-countdown').textContent =
      countdown > 0 ? `refreshing in ${countdown}s` : 'refreshing…';
    if (countdown <= 0) {
      clearInterval(timer);
      fetchData().then(startCountdown);
    }
  }, 1000);
}

// ── Live fast-poll (10s) — swaps only the rate-limit card ───────────────────────
// The 60s full refresh stays untouched. /api/live reads statusline files only
// (no transcript parse). Paused while the tab is hidden to stop background churn.
async function fetchLive() {
  if (document.hidden) return;
  try {
    const res = await fetch('/api/live?live_timeout=' + getTimeoutSecs());
    if (!res.ok) return;
    const live = await res.json();
    const card = document.querySelector('.rl-card');
    if (!card) return;
    const tmp = document.createElement('div');
    tmp.innerHTML = rateLimitCard(live);
    card.replaceWith(tmp.firstElementChild);
    drawRateLimitCharts(live);
    if (lastData) lastData.live = live;  // keep next full render consistent
  } catch (e) { /* transient poll failure — the 60s refresh recovers */ }
}

// ── Theme toggle (light / dark / auto) ───────────────────────────────────────────
const THEME_KEY = 'cc_theme';

function applyTheme(mode) {
  if (mode === 'light' || mode === 'dark') {
    document.documentElement.setAttribute('data-theme', mode);
  } else {
    document.documentElement.removeAttribute('data-theme');  // auto → follow OS
  }
  document.querySelectorAll('#theme-toggle .theme-btn').forEach(b =>
    b.classList.toggle('active', b.dataset.themeMode === mode));
}

function initTheme() {
  const mode = localStorage.getItem(THEME_KEY) || 'auto';
  applyTheme(mode);
  document.getElementById('theme-toggle').addEventListener('click', e => {
    const btn = e.target.closest('.theme-btn');
    if (!btn) return;
    const next = btn.dataset.themeMode;
    localStorage.setItem(THEME_KEY, next);
    applyTheme(next);
    // Repaint canvases so chart colors track the new theme
    fetchData();
  });
}

initTheme();
readStateFromURL();
fetchData().then(startCountdown);
setInterval(fetchLive, 10000);
