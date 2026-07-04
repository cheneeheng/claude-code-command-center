// ── Render ─────────────────────────────────────────────────────────────────────
function render(data) {
  lastData = data;
  const { stats, sessions, live } = data;
  const main = document.getElementById('main');

  const range = getRange();
  // Suffix for cards whose numbers are scoped to the active range, so a card's
  // window is legible without reading it off the range toggle. Cards that ignore
  // the range (This Month, Plan Value, Activity profile, Top Tools) omit it, and
  // the daily charts / heatmap keep their own accurate "(last N days/12 months)".
  const RANGE_LABEL = { '7d': 'last 7 days', '30d': 'last 30 days',
    '90d': 'last 90 days', '12m': 'last 12 months', 'all': 'all time' };
  const rangeSuffix = ` (${RANGE_LABEL[range] || range})`;
  const htmlEsc = s => String(s).replace(/[&<>"']/g,
    c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  // JS-string-safe arg for inline onclick handlers (values here are folder names,
  // model ids, ISO dates, hex session ids — no double quotes in practice).
  const jsArg = s => String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'");

  const rangeSelector = `
    <div class="range-toggle" role="group" aria-label="time range">
      ${['7d','30d','90d','12m','all'].map(r => {
        const on = r === range;
        return `<button class="range-btn${on ? ' active' : ''}" aria-pressed="${on}" onclick="onRangeChange('${r}')">${r}</button>`;
      }).join('')}
    </div>`;

  // Active filter chips (dismissible). Project is server-scoped; model/day/q client.
  const chipHTML = (label, value, onClear) =>
    `<button class="filter-chip" aria-label="remove ${label} filter" onclick="${onClear}">
      <span class="chip-label">${label}:</span> ${value} <span class="chip-x">✕</span></button>`;
  const chips = [];
  if (filterProject) chips.push(chipHTML('project', htmlEsc(filterProject.split('/').pop()), 'clearProject()'));
  if (filterModel) chips.push(chipHTML('model', htmlEsc(modelShort(filterModel)), 'clearModel()'));
  if (filterDay) chips.push(chipHTML('day', filterDay, 'clearDay()'));
  if (searchQuery) chips.push(chipHTML('search', '“' + htmlEsc(searchQuery) + '”', 'clearSearch()'));
  const header = `${rangeSelector}${chips.length ? `<div class="filter-chips">${chips.join('')}</div>` : ''}`;

  if (!sessions || sessions.length === 0) {
    main.innerHTML = `${header}<div class="empty">
      No Claude Code sessions found${filterProject ? ' for this project' : ''}${range !== 'all' ? ' in the last ' + range : ''}.<br>
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

  // Trend deltas vs the preceding equal-length window (null for range=all).
  const delta = stats.delta || {};
  const deltaLine = pct => {
    if (pct == null) return '';
    const up = pct >= 0;
    return `<div class="delta ${up ? 'up' : 'down'}">${up ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}%
      <span class="delta-cmp">vs prev ${range}</span></div>`;
  };

  // Cost breakdown by model
  const costSlices = (stats.by_model || [])
    .filter(m => m.model && (m.cost || 0) > 0)
    .map(m => ({ label: modelShort(m.model), value: m.cost, color: modelColor(m.model) }));

  const maxCostModel = Math.max(...(stats.by_model || []).map(m => m.cost || 0), 0.001);
  const costModelRows = (stats.by_model || []).filter(m => m.model && (m.cost || 0) > 0).map(m => `
    <div class="bar-row">
      <button class="bar-label link-muted" onclick="setModel('${jsArg(m.model)}')">${modelShort(m.model)}</button>
      <div class="bar-track"><div class="bar-fill" style="width:${(m.cost/maxCostModel*100).toFixed(1)}%;background:${modelColor(m.model)}"></div></div>
      <div class="bar-val">${fmt.usd(m.cost)}</div>
    </div>`).join('');

  const costLegendRows = costSlices.map(s => `
    <div class="legend-row">
      <div class="legend-dot" style="background:${s.color}"></div>
      <div class="legend-name">${s.label}</div>
      <div class="legend-pct">${fmt.usd(s.value)}</div>
    </div>`).join('');

  // Project bar rows (tokens + cost)
  const maxProjTok = Math.max(...(stats.by_project || []).map(p => p.tokens), 1);
  const projectRows = (stats.by_project || []).map(p => `
    <div class="bar-row">
      <button class="bar-label link-muted" title="${htmlEsc(p.project)}" onclick="setProject('${jsArg(p.project)}')">${htmlEsc(p.project.split('/').pop())}</button>
      <div class="bar-track"><div class="bar-fill" style="width:${(p.tokens/maxProjTok*100).toFixed(1)}%"></div></div>
      <div class="bar-val wide">${fmt.num(p.tokens)} · ${fmt.usd(p.cost)}</div>
    </div>`).join('');

  // Model bar rows (by tokens)
  const maxModelTok = Math.max(...(stats.by_model || []).map(m => m.tokens), 1);
  const modelRows = (stats.by_model || []).filter(m => m.model && m.tokens > 0).map(m => `
    <div class="bar-row">
      <button class="bar-label link-muted" onclick="setModel('${jsArg(m.model)}')">${modelShort(m.model)}</button>
      <div class="bar-track"><div class="bar-fill" style="width:${(m.tokens/maxModelTok*100).toFixed(1)}%;background:${modelColor(m.model)}"></div></div>
      <div class="bar-val">${fmt.num(m.tokens)}</div>
    </div>`).join('');

  // Model mix over time (stacked daily bars)
  const familyColors = {};
  (stats.model_mix || []).forEach(d =>
    Object.keys(d.per_family || {}).forEach(f => { familyColors[f] = familyColor(f); }));
  const mixFamilies = Object.keys(familyColors);
  const hasMix = mixFamilies.length > 0;
  const mixLegend = mixFamilies.map(f =>
    `<button class="legend-chip" onclick="setModel('${jsArg(f)}')"><span class="legend-dot" style="background:${familyColors[f]}"></span>${modelShort(f)}</button>`).join('');

  // Top tools
  const maxTool = Math.max(...(stats.tools || []).map(t => t.count), 1);
  const toolRows = (stats.tools || []).map(t => `
    <div class="bar-row">
      <div class="bar-label" title="${t.name}">${t.name}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${(t.count/maxTool*100).toFixed(1)}%"></div></div>
      <div class="bar-val">${fmt.num(t.count)}</div>
    </div>`).join('');

  // Expensive sessions (top 5 by cost)
  const expensiveRows = (stats.top_sessions || []).map(s => {
    const model = s.models[0] || '';
    const color = modelColor(model);
    return `<tr>
      <td style="font-size:11px"><button class="link" onclick="setSearchTo('${jsArg(s.session_id)}')">${s.session_id}</button></td>
      <td title="${htmlEsc(s.project)}"><button class="link" onclick="setProject('${jsArg(s.project)}')">${htmlEsc(s.project.split('/').pop() || '–')}</button></td>
      <td><button class="model-tag" style="background:${color}1f;color:${color}" onclick="setModel('${jsArg(model)}')">${modelShort(model)}</button></td>
      <td>${fmt.usd(s.cost_usd)}</td>
    </tr>`;
  }).join('');

  // Client display-filter pipeline over the range-scoped rows (order matters):
  // lookback → model → day → search. None of these recompute aggregates.
  const lookbackDays = getSessionLookback();
  const cutoff = lookbackDays > 0 ? Date.now() - lookbackDays * 86400000 : 0;
  const localDay = ts => {
    const d = new Date(ts);
    return isNaN(d) ? '' :
      `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  };
  const q = searchQuery.toLowerCase();
  const filteredSessions = sessions.filter(s =>
    (lookbackDays <= 0 || (s.last_ts && new Date(s.last_ts).getTime() >= cutoff)) &&
    (!filterModel || (s.models || []).some(m => modelMatches(m, filterModel))) &&
    (!filterDay || (s.last_ts && localDay(s.last_ts) === filterDay)) &&
    (!q || (s.session_id || '').toLowerCase().includes(q) || (s.project || '').toLowerCase().includes(q))
  );

  // Pagination over filtered sessions
  const pageSize = getSessionPageSize();
  const totalPages = Math.max(1, Math.ceil(filteredSessions.length / pageSize));
  if (sessionPage > totalPages) sessionPage = totalPages;
  if (sessionPage < 1) sessionPage = 1;
  const pageStart = (sessionPage - 1) * pageSize;

  // Column sort (display order only; null values sort last regardless of direction)
  const sortVal = s => sessionSort.key === 'model' ? (s.models[0] || '') : s[sessionSort.key];
  const dir = sessionSort.dir === 'asc' ? 1 : -1;
  const isNull = v => v === null || v === undefined || v === '';
  const sortedSessions = [...filteredSessions].sort((a, b) => {
    const va = sortVal(a), vb = sortVal(b);
    const na = isNull(va), nb = isNull(vb);
    if (na && nb) return 0;
    if (na) return 1;
    if (nb) return -1;
    return (va < vb ? -1 : va > vb ? 1 : 0) * dir;
  });

  const sortTh = (key, label, title) => {
    const arrow = sessionSort.key === key
      ? `<span class="sort-arrow">${sessionSort.dir === 'asc' ? '▲' : '▼'}</span>` : '';
    return `<th class="sortable"${title ? ` title="${title}"` : ''} onclick="onSortChange('${key}')">${label}${arrow}</th>`;
  };

  const pagedSessions = sortedSessions.slice(pageStart, pageStart + pageSize);

  const sessionRows = pagedSessions.map(s => {
    const model = s.models[0] || '';
    const color = modelColor(model);
    const short = modelShort(model);
    return `<tr>
      <td style="color:var(--muted);font-size:11px">${s.session_id}</td>
      <td><button class="model-tag" style="background:${color}1f;color:${color}" onclick="setModel('${jsArg(model)}')">${short}</button></td>
      <td title="${htmlEsc(s.project)}"><button class="link" onclick="setProject('${jsArg(s.project)}')">${htmlEsc(s.project.split('/').pop() || '–')}</button></td>
      <td>${fmt.num(s.total_tokens)}</td>
      <td>${fmt.num(s.input_tokens)}</td>
      <td>${fmt.num(s.output_tokens)}</td>
      <td>${s.cost_usd > 0 ? fmt.usd(s.cost_usd) : '–'}</td>
      <td>${fmt.dur(s.duration_secs)}</td>
      <td>${s.cost_per_hour != null ? fmt.usd(s.cost_per_hour) : '–'}</td>
      <td>${s.cache_hit_pct != null ? s.cache_hit_pct.toFixed(0) + '%' : '–'}</td>
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

  // Plan value card
  const planCard = stats.plan ? `
      <div class="card stat-card">
        <div class="label">Plan Value</div>
        <div class="value accent-green">${fmt.usd(stats.plan.month_value_usd)}</div>
        <div class="sub">${stats.plan.ratio.toFixed(1)}× your ${fmt.usd(stats.plan.price_usd)} plan</div>
      </div>` : `
      <div class="card stat-card">
        <div class="label">Plan Value</div>
        <div class="value muted-value">–</div>
        <div class="sub">set C4_PLAN_PRICE_USD to see plan ROI</div>
      </div>`;

  const chartDays = (stats.by_day || []).length;

  main.innerHTML = `
    ${header}

    <div class="stats-grid stats-grid-5">
      <div class="card stat-card">
        <div class="label">Total Tokens${rangeSuffix}</div>
        <div class="value accent-amber">${fmt.num(stats.total_tokens)}</div>
        <div class="sub">${stats.total_sessions} sessions</div>
        ${deltaLine(delta.tokens_pct)}
      </div>
      <div class="card stat-card">
        <div class="label">Est. API Cost${rangeSuffix}</div>
        <div class="value accent-purple">${fmt.usd(stats.total_cost_usd)}</div>
        <div class="sub">based on API pricing</div>
        ${deltaLine(delta.cost_pct)}
      </div>
      <div class="card stat-card">
        <div class="label">Cache Savings${rangeSuffix}</div>
        <div class="value accent-green">${fmt.usd(stats.cache_savings_usd)}</div>
        <div class="sub">${fmt.usd(stats.cost_without_cache_usd)} without caching</div>
      </div>
      <div class="card stat-card">
        <div class="label">This Month</div>
        <div class="value accent-blue">${fmt.usd(stats.month_cost_usd)}</div>
        <div class="sub" title="Calendar month to date — not affected by the range filter">≈ ${fmt.usd(stats.month_projected_usd)} projected</div>
      </div>
      ${planCard}
    </div>

    ${rateLimitCard(live)}

    ${stats.heatmap && stats.heatmap.length ? `
    <div class="card">
      <div class="section-title">Activity — daily tokens (last 12 months)</div>
      ${heatmapHTML(stats.heatmap)}
    </div>` : ''}

    <div class="charts-row">
      <div class="card">
        <div class="section-title">Daily Token Usage (last ${chartDays} days)</div>
        <canvas id="daily-chart"></canvas>
      </div>
      <div class="card">
        <div class="section-title">Token Breakdown${rangeSuffix}</div>
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
        <div class="section-title">Daily Cost (last ${chartDays} days)</div>
        <canvas id="cost-daily-chart"></canvas>
      </div>
      <div class="card">
        <div class="section-title">Cost by Model${rangeSuffix}</div>
        ${costSlices.length > 0 ? `
        <div class="donut-wrap">
          <canvas id="cost-donut-chart" class="donut-canvas"></canvas>
          <div class="donut-legend">${costLegendRows}</div>
        </div>
        <div style="margin-top:20px">${costModelRows}</div>
        ` : '<div class="muted-note">No cost data</div>'}
      </div>
    </div>

    <div class="card">
      <div class="section-title">Model mix over time (last ${chartDays} days)</div>
      ${hasMix
        ? `<div class="mix-legend">${mixLegend}</div><canvas id="model-mix-chart"></canvas>`
        : '<div class="muted-note">No model data</div>'}
    </div>

    <div class="card">
      <div class="section-title">Activity profile — tokens by hour × weekday</div>
      ${hourDowHTML(stats.hour_dow)}
    </div>

    <div class="bottom-row">
      <div class="card">
        <div class="section-title">Expensive Sessions${rangeSuffix}</div>
        ${expensiveRows ? `<table>
          <thead><tr><th>Session</th><th>Project</th><th>Model</th><th>Cost</th></tr></thead>
          <tbody>${expensiveRows}</tbody>
        </table>` : '<div class="muted-note">No session data</div>'}
      </div>
      <div class="card">
        <div class="section-title">Top Tools</div>
        ${toolRows || '<div class="muted-note">No tool data</div>'}
      </div>
    </div>

    <div class="bottom-row">
      <div class="card">
        <div class="section-title">Top Projects by Tokens${rangeSuffix}</div>
        ${projectRows || '<div class="muted-note">No project data</div>'}
      </div>
      <div class="card">
        <div class="section-title">Usage by Model${rangeSuffix}</div>
        ${modelRows || '<div class="muted-note">No model data</div>'}
      </div>
    </div>

    <div class="card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <div class="section-title" style="margin:0">Recent Sessions${rangeSuffix}</div>
        <div style="display:flex;align-items:center;gap:6px;font-family:var(--mono);font-size:11px;color:var(--muted)">
          <input id="session-search" class="timeout-input search-input" type="search"
            placeholder="search id / project" value="${htmlEsc(searchQuery)}"
            aria-label="search sessions" oninput="onSearchInput(this)">
          <span style="color:var(--border2);margin:0 4px">·</span>
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
          <span style="color:var(--border2);margin:0 4px">·</span>
          <a class="csv-link" href="/api/export.csv?range=${range}${filterProject ? '&project=' + encodeURIComponent(filterProject) : ''}">export csv</a>
          <span style="color:var(--border2);margin:0 4px">·</span>
          <a class="csv-link" href="/api/report.md?range=${range}${filterProject ? '&project=' + encodeURIComponent(filterProject) : ''}">export report</a>
        </div>
      </div>
      <div class="sessions-wrap">
        <table>
          <thead>
            <tr>
              ${sortTh('session_id', 'Session')}
              ${sortTh('model', 'Model')}
              ${sortTh('project', 'Project')}
              ${sortTh('total_tokens', 'Tokens')}
              ${sortTh('input_tokens', 'Input (direct)', 'Non-cached input tokens only; cache_read/write shown in total')}
              ${sortTh('output_tokens', 'Output')}
              ${sortTh('cost_usd', 'Cost')}
              ${sortTh('duration_secs', 'Duration')}
              ${sortTh('cost_per_hour', '$/hr', 'Estimated cost per active hour; blank for sessions under 5 min')}
              ${sortTh('cache_hit_pct', 'Cache %', 'Cache-read share of input tokens')}
              ${sortTh('last_ts', 'Last active')}
            </tr>
          </thead>
          <tbody>${sessionRows || '<tr><td colspan="11" class="muted-note" style="padding:16px 0">No sessions match the current filters.</td></tr>'}</tbody>
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

  if (refocusSearch) {
    refocusSearch = false;
    const si = document.getElementById('session-search');
    if (si) { si.focus(); try { si.setSelectionRange(si.value.length, si.value.length); } catch (e) {} }
  }

  requestAnimationFrame(() => {
    const dc = document.getElementById('daily-chart');
    if (dc) makeBarChart(dc, stats.by_day, { valueKey: 'tokens', onBarClick: d => setDay(d.date) });

    const costDc = document.getElementById('cost-daily-chart');
    if (costDc) makeBarChart(costDc, stats.by_day, {
      valueKey:   'cost',
      barColor:   cssVar('--secondary'),
      hoverColor: cssVar('--secondary-hi'),
      formatTip:  d => d.date + ': ' + fmt.usd(d.cost || 0),
      formatY:    v => v >= 1 ? '$'+v.toFixed(1) : v >= 0.01 ? '$'+v.toFixed(2) : v > 0 ? '<$0.01' : '$0',
      onBarClick: d => setDay(d.date),
    });

    const donut = document.getElementById('donut-chart');
    if (donut) drawDonut(donut, tokenSlices);

    const costDonut = document.getElementById('cost-donut-chart');
    if (costDonut) drawDonut(costDonut, costSlices);

    const mix = document.getElementById('model-mix-chart');
    if (mix) makeStackedBarChart(mix, stats.model_mix, familyColors);

    drawRateLimitCharts(live);
  });
}
