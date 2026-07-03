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

  canvas.style.cursor = opts.onBarClick ? 'pointer' : 'crosshair';
  canvas.addEventListener('mousemove', onMove);
  canvas.addEventListener('mouseleave', () => { hoveredIdx = -1; draw(); tip.style.display = 'none'; });
  if (opts.onBarClick) {
    canvas.addEventListener('click', e => {
      const rect = canvas.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      for (let i = 0; i < bars.length; i++) {
        if (mx >= bars[i].x && mx <= bars[i].x + bars[i].w) { opts.onBarClick(bars[i].d); break; }
      }
    });
  }
  draw();
}

// ── Stacked bar chart (model mix over time) ───────────────────────────────────
// days: [{date, per_family:{fam:tokens}}]; familyColors: {fam:color}. Reuses the
// bar chart's axis/dpr/tooltip patterns; each bar stacks its families bottom-up.
function makeStackedBarChart(canvas, days, familyColors) {
  const families = Object.keys(familyColors);
  const H = 160;
  let bars = [];
  let hoveredIdx = -1;
  const tip = getBarTip();

  const dayTotal = d => families.reduce((a, f) => a + (d.per_family[f] || 0), 0);
  const formatY = v => v >= 1e6 ? (v/1e6).toFixed(1)+'M' : v >= 1e3 ? (v/1e3).toFixed(0)+'K' : String(Math.round(v));

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

    const maxVal = Math.max(...days.map(dayTotal), 1);
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
      ctx.fillStyle = axisColor;
      ctx.font = "9px 'JetBrains Mono', monospace";
      ctx.textAlign = 'right';
      ctx.fillText(formatY(maxVal * (1 - gi / 2)), pad.left - 4, gy + 3);
    }

    days.forEach((d, i) => {
      const x = pad.left + i * gap + (gap - barW) / 2;
      bars.push({ x, w: barW, d });
      let yBottom = pad.top + chartH;
      families.forEach(f => {
        const val = d.per_family[f] || 0;
        if (val <= 0) return;
        const segH = (val / maxVal) * chartH;
        const y = yBottom - segH;
        ctx.fillStyle = familyColors[f];
        if (i === hoveredIdx) ctx.globalAlpha = 0.85;
        ctx.fillRect(x, y, barW, segH);
        ctx.globalAlpha = 1;
        yBottom = y;
      });

      if (i === 0 || i === days.length - 1 || i % 5 === 0) {
        ctx.fillStyle = axisColor;
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
      const d = bars[found].d;
      const lines = families
        .filter(f => (d.per_family[f] || 0) > 0)
        .map(f => `${modelShort(f)}: ${fmt.num(d.per_family[f])}`);
      tip.textContent = d.date + (lines.length ? ' — ' + lines.join(', ') : ': no activity');
      tip.style.display = 'block';
      tip.style.left = Math.min(e.clientX + 12, window.innerWidth - 220) + 'px';
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

// ── Sparkline line chart (rate-limit history) ─────────────────────────────────
// points: [[ts, pct]]. Single polyline + fill, y fixed to 0–100%. Reuses the
// bar chart's dpr handling; no axis/tooltip (the card labels carry the numbers).
function makeLineChart(canvas, points, opts) {
  opts = opts || {};
  const color = opts.color || cssVar('--secondary');
  const H = 36;
  const dpr = window.devicePixelRatio || 1;
  const W = canvas.offsetWidth || 200;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.height = H + 'px';
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, W, H);
  if (!points || points.length < 2) return;

  const xs = points.map(p => p[0]);
  const minX = Math.min(...xs), spanX = (Math.max(...xs) - minX) || 1;
  const pad = { top: 4, bottom: 4 };
  const ch = H - pad.top - pad.bottom;
  const x = t => ((t - minX) / spanX) * W;
  const y = pct => pad.top + (1 - Math.min(Math.max(pct, 0), 100) / 100) * ch;

  ctx.beginPath();
  ctx.moveTo(x(points[0][0]), H);
  points.forEach(p => ctx.lineTo(x(p[0]), y(p[1])));
  ctx.lineTo(x(points[points.length - 1][0]), H);
  ctx.closePath();
  ctx.fillStyle = color + '22';
  ctx.fill();

  ctx.beginPath();
  points.forEach((p, i) => i === 0 ? ctx.moveTo(x(p[0]), y(p[1])) : ctx.lineTo(x(p[0]), y(p[1])));
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.5;
  ctx.stroke();
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
