const fmt = {
  num: n => n >= 1e9 ? (n/1e9).toFixed(2)+'B' :
            n >= 1e6 ? (n/1e6).toFixed(2)+'M' :
            n >= 1e3 ? (n/1e3).toFixed(1)+'K' : String(n),
  usd: n => n < 0.01 ? '<$0.01' : '$' + n.toFixed(2),
  ts:  s => {
    if (!s) return '–';
    const d = new Date(s.replace(' ', 'T').replace(/([+-]\d{2}:\d{2}|Z)?$/, m => m || 'Z'));
    if (isNaN(d)) return s.slice(0, 16).replace('T', ' ');
    return d.toLocaleDateString(undefined, {month:'short',day:'numeric'}) + ' ' +
           d.toLocaleTimeString(undefined, {hour:'2-digit',minute:'2-digit'});
  }
};

const cssVar = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
