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
