// ── Activity heatmap (GitHub-style calendar, fed by stats.heatmap) ────────────
// Pure display: maps the server's per-day tokens onto 5 intensity levels
// (quartiles of the non-zero days) and lays them out as week columns.
function heatmapHTML(days) {
  if (!days || days.length === 0) return '';

  const nz = days.map(d => d.tokens).filter(v => v > 0).sort((a, b) => a - b);
  const q = p => nz.length ? nz[Math.min(nz.length - 1, Math.floor(p * nz.length))] : 0;
  const t1 = q(0.25), t2 = q(0.5), t3 = q(0.75);
  const level = v => v <= 0 ? 0 : v <= t1 ? 1 : v <= t2 ? 2 : v <= t3 ? 3 : 4;

  const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  // Pad the front so the first column starts on a Sunday, then cut into weeks.
  const lead = new Date(days[0].date + 'T00:00:00').getDay();
  const cells = Array(lead).fill(null).concat(days);
  const weeks = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));

  let lastMonth = -1;
  const weekCols = weeks.map(week => {
    // Label a column when the month changes within it.
    let label = '';
    for (const d of week) {
      if (!d) continue;
      const m = new Date(d.date + 'T00:00:00').getMonth();
      if (m !== lastMonth) { label = MONTHS[m]; lastMonth = m; }
      break;
    }
    const cellDivs = week.map(d => {
      if (!d) return '<div class="hm-cell pad"></div>';
      const tip = d.tokens > 0
        ? `${d.date} · ${fmt.num(d.tokens)} tok · ${fmt.usd(d.cost)} · ${d.sessions} session${d.sessions === 1 ? '' : 's'}`
        : `${d.date} · no activity`;
      return `<div class="hm-cell l${level(d.tokens)}" title="${tip}"></div>`;
    }).join('');
    return `<div class="hm-week"><div class="hm-month">${label}</div>${cellDivs}</div>`;
  }).join('');

  return `
    <div class="hm-scroll">
      <div class="hm-grid">
        <div class="hm-week hm-daylabels">
          <div class="hm-month"></div>
          ${['','Mon','','Wed','','Fri',''].map(d => `<div class="hm-cell hm-day">${d}</div>`).join('')}
        </div>
        ${weekCols}
      </div>
    </div>
    <div class="hm-legend">
      less
      ${[0,1,2,3,4].map(l => `<div class="hm-cell l${l}"></div>`).join('')}
      more
    </div>`;
}
