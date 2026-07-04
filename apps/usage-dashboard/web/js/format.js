const fmt = {
  num: n => n >= 1e9 ? (n/1e9).toFixed(2)+'B' :
            n >= 1e6 ? (n/1e6).toFixed(2)+'M' :
            n >= 1e3 ? (n/1e3).toFixed(1)+'K' : String(n),
  usd: n => n < 0.01 ? '<$0.01' : '$' + n.toFixed(2),
  dur: s => {
    if (!s || s <= 0) return '–';
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
    if (m > 0) return `${m}m`;
    return `${s}s`;
  },
  until: ts => {
    if (ts == null) return '—';
    const t = typeof ts === 'number' ? (ts > 1e12 ? ts : ts * 1000) : Date.parse(ts);
    if (isNaN(t)) return '—';
    let secs = Math.round((t - Date.now()) / 1000);
    if (secs <= 0) return 'now';
    const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m`;
    return `${secs}s`;
  },
  ts:  s => {
    if (!s) return '–';
    const d = new Date(s.replace(' ', 'T').replace(/([+-]\d{2}:\d{2}|Z)?$/, m => m || 'Z'));
    if (isNaN(d)) return s.slice(0, 16).replace('T', ' ');
    return d.toLocaleDateString(undefined, {month:'short',day:'numeric'}) + ' ' +
           d.toLocaleTimeString(undefined, {hour:'2-digit',minute:'2-digit'});
  }
};

const cssVar = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
