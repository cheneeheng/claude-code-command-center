// ── Render ─────────────────────────────────────────────────────────────────────
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

  // Column sort (display order only; server data stays untouched)
  const sortVal = s => sessionSort.key === 'model' ? (s.models[0] || '') : (s[sessionSort.key] ?? '');
  const dir = sessionSort.dir === 'asc' ? 1 : -1;
  const sortedSessions = [...filteredSessions].sort((a, b) => {
    const va = sortVal(a), vb = sortVal(b);
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
        <div class="label">Est. API Cost</div>
        <div class="value accent-purple">${fmt.usd(stats.total_cost_usd)}</div>
        <div class="sub">based on API pricing</div>
      </div>
      <div class="card stat-card">
        <div class="label">Cache Savings</div>
        <div class="value accent-green">${fmt.usd(stats.cache_savings_usd)}</div>
        <div class="sub">${fmt.usd(stats.cost_without_cache_usd)} without caching</div>
      </div>
      <div class="card stat-card">
        <div class="label">This Month</div>
        <div class="value accent-blue">${fmt.usd(stats.month_cost_usd)}</div>
        <div class="sub">≈ ${fmt.usd(stats.month_projected_usd)} projected</div>
      </div>
    </div>

    ${rateLimitCard(live)}

    ${stats.heatmap && stats.heatmap.length ? `
    <div class="card hm-card">
      <div class="section-title">Activity — daily tokens (last 12 months)</div>
      ${heatmapHTML(stats.heatmap)}
    </div>` : ''}

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
          <span style="color:var(--border2);margin:0 4px">·</span>
          <a class="csv-link" href="/api/export.csv">export csv</a>
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
              ${sortTh('last_ts', 'Last active')}
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
