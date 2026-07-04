// ── Rate limit card ────────────────────────────────────────────────────────────
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

  const history = live.history || {};
  const forecast = live.forecast || {};

  const limitCol = (label, obj, sparkId, hist, etaTs) => {
    if (!obj) return '<div></div>';
    const c = pctColor(obj.used_pct);
    const spark = (hist || []).length >= 2 ? `<canvas class="rl-spark" id="${sparkId}"></canvas>` : '';
    const eta = etaTs != null
      ? `<div class="rl-note">at current pace: cap ~${new Date(etaTs * 1000).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}</div>`
      : '';
    const reset = obj.resets_at
      ? `<div class="rl-note">resets in ${fmt.until(obj.resets_at)}</div>`
      : '';
    return `<div>
      <div style="font-size:10px;color:var(--muted);font-family:var(--mono)">${label}</div>
      <div style="font-size:20px;font-family:var(--mono);font-weight:500;color:${c};line-height:1.2">${obj.used_pct.toFixed(0)}%</div>
      ${miniBar(obj.used_pct, c)}
      ${spark}${eta}${reset}
    </div>`;
  };

  const limitCols = () => `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
      ${limitCol('5-HOUR', live.five_hour, 'rl-spark-5h', history.five_hour, forecast.five_hour_eta_ts)}
      ${limitCol('7-DAY', live.seven_day, 'rl-spark-7d', history.seven_day, forecast.seven_day_eta_ts)}
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
    ${limitCols()}
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

// Draw the rate-limit history sparklines after the card HTML is in the DOM.
// Called by render() (full refresh) and the 10s live poll (card-only swap).
function drawRateLimitCharts(live) {
  const hist = (live && live.history) || {};
  const c5 = document.getElementById('rl-spark-5h');
  if (c5 && (hist.five_hour || []).length >= 2) makeLineChart(c5, hist.five_hour, { color: cssVar('--secondary') });
  const c7 = document.getElementById('rl-spark-7d');
  if (c7 && (hist.seven_day || []).length >= 2) makeLineChart(c7, hist.seven_day, { color: cssVar('--accent') });
}
