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
