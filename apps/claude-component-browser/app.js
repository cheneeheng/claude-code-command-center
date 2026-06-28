let members = [];
let preview = true;  // render markdown by default; toggled per session in the detail pane
const md = window.markdownit();  // html:false by default -> raw HTML is escaped, links sanitized
const listEl = document.getElementById('list');
const detailEl = document.getElementById('detail');
const countEl = document.getElementById('count');
const searchEl = document.getElementById('search');

function render(filter) {
  const q = filter.trim().toLowerCase();
  const matches = members.filter(m =>
    !q || m.name.toLowerCase().includes(q) || m.scope.toLowerCase().includes(q) ||
    m.kind.toLowerCase().includes(q) || m.plugin.toLowerCase().includes(q) ||
    m.source.toLowerCase().includes(q) || m.description.toLowerCase().includes(q));

  listEl.replaceChildren();
  let currentGroup = null;
  let groupBody = null;
  let groupCountEl = null;
  let groupCount = 0;
  const flushCount = () => { if (groupCountEl) groupCountEl.textContent = groupCount; };
  for (const m of matches) {
    const group = m.plugin || '(loose)';
    if (group !== currentGroup) {
      flushCount();
      currentGroup = group;
      groupCount = 0;
      const details = document.createElement('details');
      details.className = 'group';
      details.open = true;
      const summary = document.createElement('summary');
      const label = document.createElement('span');
      label.textContent = group;
      groupCountEl = document.createElement('span');
      groupCountEl.className = 'group-count';
      summary.append(label, groupCountEl);
      groupBody = document.createElement('div');
      groupBody.className = 'group-body';
      details.append(summary, groupBody);
      listEl.appendChild(details);
    }
    groupCount++;
    const btn = document.createElement('button');
    btn.className = m.shadowed ? 'skill-btn shadowed' : 'skill-btn';
    const nm = document.createElement('span');
    nm.textContent = m.name;
    const badges = document.createElement('span');
    badges.className = 'badges';
    const kd = document.createElement('span');
    kd.className = 'kind';
    kd.dataset.kind = m.kind;
    kd.textContent = m.kind;
    const sc = document.createElement('span');
    sc.className = 'scope';
    sc.textContent = m.scope;
    badges.append(kd, sc);
    if (m.source === 'loose') {
      const src = document.createElement('span');
      src.className = 'source';
      src.textContent = 'loose';
      badges.append(src);
    }
    btn.append(nm, badges);
    btn.title = m.shadowed
      ? `${m.description}\n(shadowed by a higher-precedence ${m.kind} of the same name)`
      : m.description;
    btn.addEventListener('click', () => select(m, btn));
    groupBody.appendChild(btn);
  }
  flushCount();
  countEl.textContent = `${matches.length} of ${members.length} items`;
}

async function select(m, btn) {
  for (const b of listEl.querySelectorAll('.skill-btn'))
    b.removeAttribute('aria-current');
  btn.setAttribute('aria-current', 'true');

  detailEl.replaceChildren();
  const meta = document.createElement('p');
  meta.className = 'meta';
  const parts = [
    m.kind, m.scope,
    m.source === 'loose' ? 'loose' : m.plugin,
    m.marketplace, m.version ? `v${m.version}` : '',
    m.shadowed ? 'shadowed' : '',
  ].filter(Boolean);
  meta.textContent = parts.join(' · ');
  const title = document.createElement('h2');
  title.textContent = m.name;
  const desc = document.createElement('p');
  desc.className = 'desc';
  desc.textContent = m.description;
  detailEl.append(meta, title, desc);

  // Only skills/agents are markdown; hooks carry a pre-rendered plain-text body.
  const isMarkdown = m.kind === 'skill' || m.kind === 'agent';
  let bodyText = '';
  const content = document.createElement('div');
  content.textContent = 'Loading…';

  const paint = () => {
    content.replaceChildren();
    if (isMarkdown && preview) {
      content.className = 'markdown-body';
      content.innerHTML = md.render(bodyText);
    } else {
      content.className = 'raw-body';
      const pre = document.createElement('pre');
      pre.textContent = bodyText;
      content.appendChild(pre);
    }
  };

  if (isMarkdown) {
    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'view-toggle';
    const sync = () => { toggle.textContent = preview ? 'View raw' : 'View rendered'; };
    sync();
    toggle.addEventListener('click', () => { preview = !preview; sync(); paint(); });
    detailEl.append(toggle);
  }
  detailEl.append(content);

  try {
    const res = await fetch(`/api/member?id=${m.id}`);
    if (res.ok) { bodyText = await res.text(); paint(); }
    else { content.className = 'raw-body'; content.textContent = 'Could not load this item.'; }
  } catch {
    content.className = 'raw-body';
    content.textContent = 'Could not load this item.';
  }
}

searchEl.addEventListener('input', () => render(searchEl.value));

fetch('/api/members')
  .then(r => r.json())
  .then(data => { members = data; render(''); })
  .catch(() => { countEl.textContent = 'Failed to load items.'; });
