// #/session/{id} — planning chat: transcript + streaming pane + input.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.session = async function sessionView(main, { id }) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading session…"));
  const meta = await RT.api.get(`/api/sessions/${encodeURIComponent(id)}`);
  const project = meta.project;

  // --- header -----------------------------------------------------------------
  const costChip = h("span", { class: "cost-chip" },
    `session total: ${RT.fmt.costShort(meta.cost_est_usd)}`);
  const header = h("h2", {},
    h("a", { href: `#/repo/${encodeURIComponent(project)}` }, `◂ ${project}`),
    ` planning session `,
    h("span", { class: "chip state-queued" }, meta.status),
    " ", costChip);

  // --- transcript, turn-grouped --------------------------------------------------
  const turnCost = {};
  for (const t of meta.turns) turnCost[t.n] = t;
  const turns = new Map();
  for (const entry of meta.transcript) {
    if (!turns.has(entry.n)) turns.set(entry.n, []);
    turns.get(entry.n).push(entry);
  }
  const transcript = h("div", {});
  for (const [n, entries] of turns) {
    const tools = entries.filter((e) => e.kind === "tool");
    const turnEl = h("div", { class: "turn" });
    for (const e of entries) {
      if (e.kind === "user") turnEl.append(h("div", { class: "msg-user" }, e.text));
      else if (e.kind === "text") { const d = h("div", { class: "msg-claude" }); RT.md.into(d, e.text); turnEl.append(d); }
      else if (e.kind === "status") turnEl.append(h("div", { class: "msg-status" }, e.text));
      else if (e.kind === "error") turnEl.append(h("div", { class: "msg-error" }, e.text));
    }
    if (tools.length) {
      turnEl.append(h("details", {},
        h("summary", {}, `show activity (${tools.length} tool call${tools.length === 1 ? "" : "s"})`),
        ...tools.map((t) => h("div", { class: "msg-tool" }, t.text))));
    }
    const cost = turnCost[n];
    if (cost) {
      turnEl.append(h("div", { class: "turn-foot" },
        `turn ${n} · ${RT.fmt.cost(cost.cost_est_usd, cost.cost_reported_usd)}`));
    }
    transcript.append(turnEl);
  }
  if (!turns.size) transcript.append(h("div", { class: "empty" }, "no transcript yet"));

  // --- produced plans banner -------------------------------------------------------
  const banners = h("div", {});
  for (const p of meta.produced_plans) {
    const banner = h("div", { class: "plan-banner" },
      `New plan: `, h("code", {}, p.slug),
      h("a", { href: `#/repo/${encodeURIComponent(project)}/plan/${p.slug}` }, "View"));
    if (RT.roundOpen()) {
      banner.append(h("button", { onclick: () => RT.addToRound(project, p.slug) }, "Add to round"));
    }
    banners.append(banner);
  }

  // --- streaming pane + controls -------------------------------------------------------
  const streamPane = h("div", { class: "stream-pane", hidden: "" });
  const controls = h("div", { class: "chat-input" });

  function renderControls() {
    controls.replaceChildren();
    if (meta.status === "streaming") {
      controls.append(h("button", {
        class: "btn-danger",
        onclick: async () => { await RT.api.post(`/api/sessions/${encodeURIComponent(id)}/stop`); },
      }, "Stop"));
    } else if (meta.status === "idle") {
      const box = h("textarea", { rows: "3", placeholder: "Follow-up message…" });
      const buttons = h("div", {},
        h("button", {
          class: "btn-primary",
          onclick: async () => {
            const prompt = box.value.trim();
            if (!prompt) return;
            await RT.api.post(`/api/sessions/${encodeURIComponent(id)}/message`, { prompt });
            RT.views.session(main, { id });
          },
        }, "Send"),
        " ",
        h("button", {
          onclick: async () => {
            await RT.api.post(`/api/sessions/${encodeURIComponent(id)}/close`);
            RT.views.session(main, { id });
          },
        }, "Close session"));
      // One-click "write the plan now": a canned follow-up turn — the session's
      // --resume context is the plan content; only the destination is spelled out.
      // (The user can always ask for the plan file in their own words instead.)
      if (!meta.produced_plans.length) {
        buttons.prepend(h("button", {
          class: "btn-outline",
          onclick: async () => {
            const cfg = await RT.api.get("/api/config");
            const proj = cfg.projects.find((p) => p.name === project);
            const dir = (proj && proj.planning_dir) || ".agents_workspace/planning";
            const prompt = `Based on our discussion in this session, write the agreed plan as a markdown file under \`${dir}/\` now, then reply with its repo-relative path. Do not implement anything.`;
            await RT.api.post(`/api/sessions/${encodeURIComponent(id)}/message`, { prompt });
            RT.views.session(main, { id });
          },
        }, "Create plan file"), " ");
      }
      controls.append(box, buttons);
    } else {
      controls.append(h("span", { class: "dim" }, `session is ${meta.status}`));
    }
  }
  renderControls();

  main.replaceChildren(h("div", { class: "chat" }, header, banners, transcript, streamPane, controls));

  if (meta.status === "streaming") {
    streamPane.hidden = false;
    const es = RT.sse.open(`/api/sessions/${encodeURIComponent(id)}/stream`, {
      onItem: (item) => {
        const cls = { user: "msg-user", text: "msg-claude", tool: "msg-tool", status: "msg-status", error: "msg-error" }[item.kind] || "msg-claude";
        streamPane.append(h("div", { class: cls }, item.text));
        streamPane.scrollTop = streamPane.scrollHeight;
      },
      onEnd: () => RT.views.session(main, { id }),
      onError: () => RT.views.session(main, { id }),
    });
    RT.viewCleanup = () => es.close();
  }
};

RT.router.register("#/session/{id}", (main, params) => RT.views.session(main, params));
