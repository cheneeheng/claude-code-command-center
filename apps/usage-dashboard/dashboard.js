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

function modelFamily(m) {
  const l = (m || '').toLowerCase();
  if (l.includes('fable'))  return 'fable';
  if (l.includes('opus'))   return 'opus';
  if (l.includes('sonnet')) return 'sonnet';
  if (l.includes('haiku'))  return 'haiku';
  return 'other';
}

// Assign a distinct color per model, shaded by version within its family so that
// e.g. each Opus version is a different shade of purple. Same map is used by the
// cost donut, both bar-chart sections, and the recent-sessions model tags.
const MODEL_SHADES = {
  fable:  ['#f59e0b', '#fbbf24', '#d97706', '#fcd34d', '#b45309'],
  opus:   ['#a855f7', '#c084fc', '#9333ea', '#d8b4fe', '#7e22ce'],
  sonnet: ['#3b82f6', '#60a5fa', '#2563eb', '#93c5fd', '#1d4ed8'],
  haiku:  ['#22c55e', '#4ade80', '#16a34a', '#86efac', '#15803d'],
  other:  ['#6b6b7a', '#8b8b9a', '#a1a1b0', '#525260'],
};

function buildModelColors(models) {
  const groups = {};
  models.filter(Boolean).forEach(m => { (groups[modelFamily(m)] ||= []).push(m); });
  const map = {};
  for (const [fam, list] of Object.entries(groups)) {
    [...new Set(list)].sort().forEach((m, i) => {
      const shades = MODEL_SHADES[fam];
      map[m] = shades[i % shades.length];
    });
  }
  return map;
}

function modelShort(m) {
  if (!m) return '–';
  const l = m.toLowerCase();
  // Build "Family-version" e.g. claude-opus-4-8 -> Opus-4-8, claude-sonnet-4-6 -> Sonnet-4-6
  const fam = l.includes('fable') ? 'Fable' : l.includes('opus') ? 'Opus' : l.includes('sonnet') ? 'Sonnet' : l.includes('haiku') ? 'Haiku' : null;
  if (fam) {
    const ver = m.replace(/^claude-/i, '').replace(new RegExp(fam, 'i'), '')
                 .replace(/-?\d{8}$/, '').replace(/^-+/, '');
    return ver ? `${fam}-${ver}` : fam;
  }
  return m.split('-').pop() || m;
}

// ── Interactive bar chart ─────────────────────────────────────────────────────
let _barTip = null;
function getBarTip() {
  if (!_barTip) {
    _barTip = document.createElement('div');
    _barTip.className = 'bar-tip';
    document.body.appendChild(_barTip);
  }
  return _barTip;
}

function makeBarChart(canvas, days, opts) {
  opts = opts || {};
  const valueKey   = opts.valueKey   || 'tokens';
  const barColor   = opts.barColor   || cssVar('--accent');
  const hoverColor = opts.hoverColor || cssVar('--accent-hi');
  const formatTip  = opts.formatTip  || (d => d.date + ': ' + fmt.num(d[valueKey] || 0));
  const formatY    = opts.formatY    || (v =>
    v >= 1e6 ? (v/1e6).toFixed(1)+'M' : v >= 1e3 ? (v/1e3).toFixed(0)+'K' : String(Math.round(v))
  );

  const H = 140;
  let bars = [];
  let hoveredIdx = -1;
  const tip = getBarTip();

  function draw() {
    const dpr = window.devicePixelRatio || 1;
    const W = canvas.offsetWidth || 600;
    canvas.width  = W * dpr;
    canvas.height = H * dpr;
    canvas.style.height = H + 'px';
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    bars = [];
    if (!days || days.length === 0) return;

    const vals = days.map(d => d[valueKey] || 0);
    const maxVal = Math.max(...vals, 1);
    const pad = { top: 8, right: 0, bottom: 24, left: 56 };
    const chartW = W - pad.left - pad.right;
    const chartH = H - pad.top - pad.bottom;
    const barW = Math.max(2, (chartW / days.length) - 2);
    const gap  = chartW / days.length;

    ctx.clearRect(0, 0, W, H);

    const gridColor = cssVar('--border');
    const axisColor = cssVar('--fg-muted');

    for (let gi = 0; gi <= 2; gi++) {
      const gy = pad.top + (chartH / 2) * gi;
      ctx.beginPath();
      ctx.strokeStyle = gridColor;
      ctx.lineWidth = 1;
      ctx.moveTo(pad.left, gy);
      ctx.lineTo(pad.left + chartW, gy);
      ctx.stroke();
      const gval = maxVal * (1 - gi / 2);
      ctx.fillStyle = axisColor;
      ctx.font = "9px 'JetBrains Mono', monospace";
      ctx.textAlign = 'right';
      ctx.fillText(formatY(gval), pad.left - 4, gy + 3);
    }

    days.forEach((d, i) => {
      const val  = d[valueKey] || 0;
      const barH = val > 0 ? Math.max(2, (val / maxVal) * chartH) : 0;
      const x = pad.left + i * gap + (gap - barW) / 2;
      const y = pad.top + chartH - barH;
      bars.push({ x, y, w: barW, h: barH, d });

      const isHovered = (i === hoveredIdx);
      if (barH > 0) {
        if (isHovered) {
          ctx.fillStyle = hoverColor;
        } else {
          const grad = ctx.createLinearGradient(0, y, 0, pad.top + chartH);
          grad.addColorStop(0, barColor);
          grad.addColorStop(1, barColor + '4d');
          ctx.fillStyle = grad;
        }
        ctx.beginPath();
        ctx.roundRect(x, y, barW, barH, [2, 2, 0, 0]);
        ctx.fill();
      }

      if (i === 0 || i === days.length - 1 || i % 5 === 0) {
        ctx.fillStyle = isHovered ? cssVar('--fg') : axisColor;
        ctx.font = "10px 'JetBrains Mono', monospace";
        ctx.textAlign = 'center';
        ctx.fillText(d.date.slice(5), x + barW / 2, H - 4);
      }
    });
  }

  function onMove(e) {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    let found = -1;
    for (let i = 0; i < bars.length; i++) {
      if (mx >= bars[i].x && mx <= bars[i].x + bars[i].w) { found = i; break; }
    }
    if (found !== hoveredIdx) { hoveredIdx = found; draw(); }
    if (found >= 0) {
      tip.textContent = formatTip(bars[found].d);
      tip.style.display = 'block';
      tip.style.left = Math.min(e.clientX + 12, window.innerWidth - 170) + 'px';
      tip.style.top  = (e.clientY - 36) + 'px';
    } else {
      tip.style.display = 'none';
    }
  }

  canvas.style.cursor = 'crosshair';
  canvas.addEventListener('mousemove', onMove);
  canvas.addEventListener('mouseleave', () => { hoveredIdx = -1; draw(); tip.style.display = 'none'; });
  draw();
}

// ── Donut chart ───────────────────────────────────────────────────────────────
function drawDonut(canvas, slices) {
  const dpr = window.devicePixelRatio || 1;
  const SIZE = 110;
  canvas.width  = SIZE * dpr;
  canvas.height = SIZE * dpr;
  canvas.style.width  = SIZE + 'px';
  canvas.style.height = SIZE + 'px';
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);

  const active = slices.filter(s => s.value > 0);
  const total = active.reduce((a, s) => a + s.value, 0) || 1;
  const cx = SIZE/2, cy = SIZE/2, r = SIZE/2 - 6, inner = r * 0.58;
  let angle = -Math.PI / 2;

  ctx.clearRect(0, 0, SIZE, SIZE);
  active.forEach(s => {
    const sweep = (s.value / total) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, r, angle, angle + sweep);
    ctx.closePath();
    ctx.fillStyle = s.color;
    ctx.fill();
    angle += sweep;
  });

  ctx.beginPath();
  ctx.arc(cx, cy, inner, 0, Math.PI * 2);
  ctx.fillStyle = cssVar('--surface');
  ctx.fill();
}

// ── Render ─────────────────────────────────────────────────────────────────────
function timeoutInputHtml() {
  const saved = localStorage.getItem('cc_live_timeout_min') || '30';
  return `<div class="timeout-control" style="margin-top:12px;padding-top:12px;border-top:1px solid var(--border)">
    <label for="live-timeout">session timeout</label>
    <input id="live-timeout" class="timeout-input" type="number" min="1" step="1" value="${saved}" onchange="onTimeoutChange(this)">
    <span class="timeout-unit">min</span>
  </div>`;
}

function rateLimitCard(live) {
  const inlineTimeout = () => `<div style="display:flex;align-items:center;gap:5px">
    <label for="live-timeout" style="color:var(--muted);font-family:var(--mono);font-size:10px;white-space:nowrap">timeout</label>
    <input id="live-timeout" class="timeout-input" type="number" min="1" step="1" value="${localStorage.getItem('cc_live_timeout_min')||'30'}" onchange="onTimeoutChange(this)">
    <span style="color:var(--muted);font-family:var(--mono);font-size:10px">min</span>
  </div>`;

  if (!live || !live.available) {
    return `<div class="card rl-card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
        <div class="section-title" style="margin:0">Live Rate Limits</div>
        ${inlineTimeout()}
      </div>
      <div style="color:var(--muted);font-family:var(--mono);font-size:12px;padding:8px 0">
        Hook not set up — install the statusline-hook tool to see live rate limits
      </div>
    </div>`;
  }
  if (!live.five_hour && !live.seven_day) {
    return `<div class="card rl-card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
        <div class="section-title" style="margin:0">Live Rate Limits</div>
        ${inlineTimeout()}
      </div>
      <div style="color:var(--muted);font-family:var(--mono);font-size:12px;padding:8px 0">
        Pro/Max only · no data yet — run a session first
      </div>
    </div>`;
  }

  const pctColor = p => p >= 90 ? 'var(--red)' : p >= 70 ? 'var(--accent2)' : 'var(--green)';

  const miniBar = (pct, color) => `
    <div class="bar-track" style="height:4px;margin-top:3px">
      <div class="bar-fill" style="width:${Math.min(pct,100)}%;background:${color}"></div>
    </div>`;

  const limitCols = (fh, sd) => `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
      ${fh ? `<div>
        <div style="font-size:10px;color:var(--muted);font-family:var(--mono)">5-HOUR</div>
        <div style="font-size:20px;font-family:var(--mono);font-weight:500;color:${pctColor(fh.used_pct)};line-height:1.2">${fh.used_pct.toFixed(0)}%</div>
        ${miniBar(fh.used_pct, pctColor(fh.used_pct))}
      </div>` : '<div></div>'}
      ${sd ? `<div>
        <div style="font-size:10px;color:var(--muted);font-family:var(--mono)">7-DAY</div>
        <div style="font-size:20px;font-family:var(--mono);font-weight:500;color:${pctColor(sd.used_pct)};line-height:1.2">${sd.used_pct.toFixed(0)}%</div>
        ${miniBar(sd.used_pct, pctColor(sd.used_pct))}
      </div>` : '<div></div>'}
    </div>`;

  const sessions = live.sessions || [];
  const multiSession = sessions.length > 0;

  const liveTs = live.ts
    ? new Date(live.ts * 1000).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit',second:'2-digit'})
    : '–';

  const sessionRows = multiSession ? sessions.map(s => {
      const ts = s.ts ? new Date(s.ts * 1000).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit',second:'2-digit'}) : '–';
      const cost = s.session_cost != null ? fmt.usd(s.session_cost) : '–';
      return `<tr>
        <td style="color:var(--muted);font-size:11px">${s.session_id}</td>
        <td style="font-size:11px">${s.model || '–'}</td>
        <td style="font-size:11px">${s.context_pct != null ? s.context_pct.toFixed(0)+'%' : '–'}</td>
        <td style="font-size:11px">${cost}</td>
        <td style="color:var(--muted);font-size:11px">${ts}</td>
      </tr>`;
    }).join('') : '';

  return `<div class="card rl-card">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px">
      <div class="section-title" style="margin:0">Live Rate Limits</div>
      <div style="display:flex;align-items:center;gap:12px">
        ${inlineTimeout()}
        <div style="font-size:10px;color:var(--muted);font-family:var(--mono)">
           · ${sessions.length} active session${sessions.length !== 1 ? 's' : ''} · updated ${liveTs}
        </div>
      </div>
    </div>
    ${limitCols(live.five_hour, live.seven_day)}
    ${multiSession ? `
    <div style="margin-top:20px;border-top:1px solid var(--border);padding-top:14px">
      <div style="font-size:10px;color:var(--muted);font-family:var(--mono);letter-spacing:0.08em;text-transform:uppercase;margin-bottom:10px">Per Session</div>
      <table style="width:100%;border-collapse:collapse;font-family:var(--mono)">
        <thead>
          <tr>
            <th style="text-align:left;font-size:10px;color:var(--muted);font-weight:400;padding-bottom:6px;border-bottom:1px solid var(--border)">Session</th>
            <th style="text-align:left;font-size:10px;color:var(--muted);font-weight:400;padding-bottom:6px;border-bottom:1px solid var(--border)">Model</th>
            <th style="text-align:left;font-size:10px;color:var(--muted);font-weight:400;padding-bottom:6px;border-bottom:1px solid var(--border)">Ctx % (1M)</th>
            <th style="text-align:left;font-size:10px;color:var(--muted);font-weight:400;padding-bottom:6px;border-bottom:1px solid var(--border)">Cost</th>
            <th style="text-align:left;font-size:10px;color:var(--muted);font-weight:400;padding-bottom:6px;border-bottom:1px solid var(--border)">Updated</th>
          </tr>
        </thead>
        <tbody>${sessionRows}</tbody>
      </table>
    </div>` : ''}
  </div>`;
}

function render(data) {
  lastData = data;
  const { stats, sessions, live } = data;
  const main = document.getElementById('main');

  if (!sessions || sessions.length === 0) {
    main.innerHTML = `<div class="empty">
      No Claude Code sessions found.<br>
      Expected logs at <code>~/.claude/projects/</code>
    </div>`;
    return;
  }

  // Token breakdown
  const tokenSlices = [
    { label: 'input',       value: stats.total_input,       color: '#3b82f6' },
    { label: 'output',      value: stats.total_output,      color: '#f59e0b' },
    { label: 'cache write', value: stats.total_cache_write, color: '#a855f7' },
    { label: 'cache read',  value: stats.total_cache_read,  color: '#22c55e' },
  ].filter(s => s.value > 0);

  const tokenBreakdown = [
    { label: 'input',       value: stats.total_input,       color: '#3b82f6', cls: 'blue'   },
    { label: 'output',      value: stats.total_output,      color: '#f59e0b', cls: ''        },
    { label: 'cache write', value: stats.total_cache_write, color: '#a855f7', cls: 'purple'  },
    { label: 'cache read',  value: stats.total_cache_read,  color: '#22c55e', cls: 'green'   },
  ];
  const maxTok = Math.max(...tokenBreakdown.map(t => t.value), 1);

  // Per-model color map (shared across cost donut, bar charts, and session tags)
  const allModels = [
    ...(stats.by_model || []).map(m => m.model),
    ...sessions.flatMap(s => s.models || []),
  ];
  const modelColorMap = buildModelColors(allModels);
  const modelColor = m => modelColorMap[m] || '#6b6b7a';

  // Cost breakdown by model
  const costSlices = (stats.by_model || [])
    .filter(m => m.model && (m.cost || 0) > 0)
    .map(m => ({ label: modelShort(m.model), value: m.cost, color: modelColor(m.model) }));

  const maxCostModel = Math.max(...(stats.by_model || []).map(m => m.cost || 0), 0.001);
  const costModelRows = (stats.by_model || []).filter(m => m.model && (m.cost || 0) > 0).map(m => `
    <div class="bar-row">
      <div class="bar-label">${modelShort(m.model)}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${(m.cost/maxCostModel*100).toFixed(1)}%;background:${modelColor(m.model)}"></div></div>
      <div class="bar-val">${fmt.usd(m.cost)}</div>
    </div>`).join('');

  const costLegendRows = costSlices.map(s => `
    <div class="legend-row">
      <div class="legend-dot" style="background:${s.color}"></div>
      <div class="legend-name">${s.label}</div>
      <div class="legend-pct">${fmt.usd(s.value)}</div>
    </div>`).join('');

  // Project bar rows
  const maxProjTok = Math.max(...(stats.by_project || []).map(p => p.tokens), 1);
  const projectRows = (stats.by_project || []).map(p => `
    <div class="bar-row">
      <div class="bar-label" title="${p.project}">${p.project.split('/').pop()}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${(p.tokens/maxProjTok*100).toFixed(1)}%"></div></div>
      <div class="bar-val">${fmt.num(p.tokens)}</div>
    </div>`).join('');

  // Model bar rows (by tokens)
  const maxModelTok = Math.max(...(stats.by_model || []).map(m => m.tokens), 1);
  const modelRows = (stats.by_model || []).filter(m => m.model && m.tokens > 0).map(m => `
    <div class="bar-row">
      <div class="bar-label">${modelShort(m.model)}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${(m.tokens/maxModelTok*100).toFixed(1)}%;background:${modelColor(m.model)}"></div></div>
      <div class="bar-val">${fmt.num(m.tokens)}</div>
    </div>`).join('');

  // Session lookback filter
  const lookbackDays = getSessionLookback();
  const cutoff = lookbackDays > 0 ? Date.now() - lookbackDays * 86400000 : 0;
  const filteredSessions = lookbackDays > 0
    ? sessions.filter(s => s.last_ts && new Date(s.last_ts).getTime() >= cutoff)
    : sessions;

  // Pagination over filtered sessions
  const pageSize = getSessionPageSize();
  const totalPages = Math.max(1, Math.ceil(filteredSessions.length / pageSize));
  if (sessionPage > totalPages) sessionPage = totalPages;
  if (sessionPage < 1) sessionPage = 1;
  const pageStart = (sessionPage - 1) * pageSize;
  const pagedSessions = filteredSessions.slice(pageStart, pageStart + pageSize);

  const sessionRows = pagedSessions.map(s => {
    const model = s.models[0] || '';
    const color = modelColor(model);
    const short = modelShort(model);
    return `<tr>
      <td style="color:var(--muted);font-size:11px">${s.session_id}</td>
      <td><span class="model-tag" style="background:${color}1f;color:${color}">${short}</span></td>
      <td title="${s.project}">${s.project.split('/').pop() || '–'}</td>
      <td>${fmt.num(s.total_tokens)}</td>
      <td>${fmt.num(s.input_tokens)}</td>
      <td>${fmt.num(s.output_tokens)}</td>
      <td>${s.cost_usd > 0 ? fmt.usd(s.cost_usd) : '–'}</td>
      <td class="ts">${fmt.ts(s.last_ts)}</td>
    </tr>`;
  }).join('');

  // Token donut legend
  const totalTok = stats.total_tokens || 1;
  const legendRows = tokenSlices.map(t => `
    <div class="legend-row">
      <div class="legend-dot" style="background:${t.color}"></div>
      <div class="legend-name">${t.label}</div>
      <div class="legend-pct">${(t.value/totalTok*100).toFixed(1)}%</div>
    </div>`).join('');

  main.innerHTML = `
    <div class="stats-grid">
      <div class="card stat-card">
        <div class="label">Total Tokens</div>
        <div class="value accent-amber">${fmt.num(stats.total_tokens)}</div>
        <div class="sub">${stats.total_sessions} sessions</div>
      </div>
      <div class="card stat-card">
        <div class="label">Output Tokens</div>
        <div class="value accent-blue">${fmt.num(stats.total_output)}</div>
        <div class="sub">generated by model</div>
      </div>
      <div class="card stat-card">
        <div class="label">Cache Savings</div>
        <div class="value accent-green">${fmt.num(stats.total_cache_read)}</div>
        <div class="sub">tokens read from cache</div>
      </div>
      <div class="card stat-card">
        <div class="label">Est. API Cost</div>
        <div class="value accent-purple">${fmt.usd(stats.total_cost_usd)}</div>
        <div class="sub">based on API pricing</div>
      </div>
    </div>

    ${rateLimitCard(live)}

    <div class="charts-row">
      <div class="card">
        <div class="section-title">Daily Token Usage (last 30 days)</div>
        <canvas id="daily-chart"></canvas>
      </div>
      <div class="card">
        <div class="section-title">Token Breakdown</div>
        <div class="donut-wrap">
          <canvas id="donut-chart" class="donut-canvas"></canvas>
          <div class="donut-legend">${legendRows}</div>
        </div>
        <div style="margin-top:20px">${tokenBreakdown.filter(t=>t.value>0).map(t=>`
          <div class="bar-row">
            <div class="bar-label">${t.label}</div>
            <div class="bar-track"><div class="bar-fill ${t.cls}" style="width:${(t.value/maxTok*100).toFixed(1)}%"></div></div>
            <div class="bar-val">${fmt.num(t.value)}</div>
          </div>`).join('')}
        </div>
      </div>
    </div>

    <div class="charts-row">
      <div class="card">
        <div class="section-title">Daily Cost (last 30 days)</div>
        <canvas id="cost-daily-chart"></canvas>
      </div>
      <div class="card">
        <div class="section-title">Cost by Model</div>
        ${costSlices.length > 0 ? `
        <div class="donut-wrap">
          <canvas id="cost-donut-chart" class="donut-canvas"></canvas>
          <div class="donut-legend">${costLegendRows}</div>
        </div>
        <div style="margin-top:20px">${costModelRows}</div>
        ` : '<div style="color:var(--muted);font-family:var(--mono);font-size:12px">No cost data</div>'}
      </div>
    </div>

    <div class="bottom-row">
      <div class="card">
        <div class="section-title">Top Projects by Tokens</div>
        ${projectRows || '<div style="color:var(--muted);font-family:var(--mono);font-size:12px">No project data</div>'}
      </div>
      <div class="card">
        <div class="section-title">Usage by Model</div>
        ${modelRows || '<div style="color:var(--muted);font-family:var(--mono);font-size:12px">No model data</div>'}
      </div>
    </div>

    <div class="card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <div class="section-title" style="margin:0">Recent Sessions</div>
        <div style="display:flex;align-items:center;gap:6px;font-family:var(--mono);font-size:11px;color:var(--muted)">
          last
          <input id="session-lookback" class="timeout-input" type="number" min="0" step="1"
            value="${lookbackDays || ''}" placeholder="all"
            onchange="onLookbackChange(this)">
          days
          <span style="color:var(--border2);margin-left:2px">(${filteredSessions.length})</span>
          <span style="color:var(--border2);margin:0 4px">·</span>
          show
          <select id="session-page-size" onchange="onPageSizeChange(this)"
            class="timeout-input" style="width:auto;padding-right:4px">
            ${[10,25,50,100].map(n => `<option value="${n}"${n===pageSize?' selected':''}>${n}</option>`).join('')}
          </select>
          rows
        </div>
      </div>
      <div class="sessions-wrap">
        <table>
          <thead>
            <tr>
              <th>Session</th>
              <th>Model</th>
              <th>Project</th>
              <th>Tokens</th>
              <th title="Non-cached input tokens only; cache_read/write shown in total">Input (direct)</th>
              <th>Output</th>
              <th>Cost</th>
              <th>Last active</th>
            </tr>
          </thead>
          <tbody>${sessionRows}</tbody>
        </table>
      </div>
      ${totalPages > 1 ? `
      <div style="display:flex;align-items:center;justify-content:flex-end;gap:10px;margin-top:14px;font-family:var(--mono);font-size:11px;color:var(--muted)">
        <button class="page-btn" onclick="onPageChange(${sessionPage - 1})" ${sessionPage <= 1 ? 'disabled' : ''}>‹ Prev</button>
        <span>Page ${sessionPage} / ${totalPages}</span>
        <button class="page-btn" onclick="onPageChange(${sessionPage + 1})" ${sessionPage >= totalPages ? 'disabled' : ''}>Next ›</button>
      </div>` : ''}
    </div>
  `;

  requestAnimationFrame(() => {
    const dc = document.getElementById('daily-chart');
    if (dc) makeBarChart(dc, stats.by_day, { valueKey: 'tokens' });

    const costDc = document.getElementById('cost-daily-chart');
    if (costDc) makeBarChart(costDc, stats.by_day, {
      valueKey:   'cost',
      barColor:   cssVar('--secondary'),
      hoverColor: cssVar('--secondary-hi'),
      formatTip:  d => d.date + ': ' + fmt.usd(d.cost || 0),
      formatY:    v => v >= 1 ? '$'+v.toFixed(1) : v >= 0.01 ? '$'+v.toFixed(2) : v > 0 ? '<$0.01' : '$0',
    });

    const donut = document.getElementById('donut-chart');
    if (donut) drawDonut(donut, tokenSlices);

    const costDonut = document.getElementById('cost-donut-chart');
    if (costDonut) drawDonut(costDonut, costSlices);
  });
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

// ── Fetch & refresh loop ───────────────────────────────────────────────────────
let countdown = 60;
let timer;

async function fetchData() {
  document.getElementById('spinner').classList.add('active');
  try {
    const res = await fetch('/api/data?live_timeout=' + getTimeoutSecs());
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
fetchData().then(startCountdown);
