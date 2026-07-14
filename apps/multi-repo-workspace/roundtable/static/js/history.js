// #/history — rounds table; #/rounds/{id} — read-only past round detail.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.history = async function historyView(main) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading history…"));
  const res = await RT.api.get("/api/rounds");
  if (!res.rounds.length) {
    main.replaceChildren(h("div", { class: "empty" }, "no rounds yet — end a turn to write history"));
    return;
  }
  const outcome = (n, label, cls) => (n > 0 ? h("span", { class: cls }, `${n} ${label}`) : null);
  const rows = res.rounds.map((r) => {
    const counts = { succeeded: 0, failed: 0, skipped: 0 };
    for (const o of r.orders) {
      if (o.state === "succeeded") counts.succeeded += 1;
      else if (o.state === "failed" || o.state === "stopped") counts.failed += 1;
      else if (o.state === "skipped") counts.skipped += 1;
    }
    const outs = [
      outcome(counts.succeeded, "succeeded", "text-success"),
      outcome(counts.failed, "failed", "text-danger"),
      outcome(counts.skipped, "skipped", "dim"),
    ].filter(Boolean);
    const row = h("tr", {
      // The one non-done round is the current one; it always sorts first.
      class: "row-link" + (r.status !== "done" ? " is-current" : ""),
      role: "link", tabindex: "0",
      onclick: () => { location.hash = `#/rounds/${r.id}`; },
      onkeydown: (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); row.click(); } },
    },
      h("td", { class: "cell-round" }, `Round ${r.number}`),
      h("td", {}, h("span", { class: `chip st-${r.status}` }, r.status)),
      h("td", { class: "numeric" }, String(r.orders.length)),
      h("td", {}, outs.length ? h("span", { class: "outcomes" }, outs) : "—"),
      h("td", { class: "numeric" }, RT.fmt.costShort(r.cost_est_usd)),
      h("td", { class: "dim" }, RT.fmt.agoIso(r.executed_at)),
      h("td", { class: "dim" }, RT.fmt.agoIso(r.closed_at)));
    return row;
  });
  main.replaceChildren(
    h("span", { class: "eyebrow" }, `Round history · ${res.rounds.length}`),
    h("p", { class: "panel-caption" },
      "every round played — open a row to revisit its orders, outcomes, and diffs"),
    h("div", { class: "card table-panel" },
      h("table", { class: "history-table" },
        h("thead", {}, h("tr", {},
          ["Round", "Status", "Orders", "Outcomes", "Cost", "Executed", "Closed"].map((c) => h("th", {}, c)))),
        h("tbody", {}, rows))));
};

RT.views.roundDetail = async function roundDetailView(main, { id }) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading round…"));
  const rnd = await RT.api.get(`/api/rounds/${encodeURIComponent(id)}`);
  const wrap = h("div", {},
    h("a", { class: "back-link", href: "#/history" }, "← History"),
    h("h2", {}, `Round ${rnd.number} `,
      h("span", { class: `chip st-${rnd.status}` }, rnd.status),
      " ", h("span", { class: "cost-chip" }, `round cost: ${RT.fmt.costShort(rnd.cost_est_usd)}`)));
  // Read-only reuse of the review card layout: recorded flags/notes/costs, replay.
  RT.views.reviewPanel(wrap, rnd, { readOnly: rnd.status === "done" });
  main.replaceChildren(wrap);
};

RT.router.register("#/history", (main) => RT.views.history(main));
RT.router.register("#/rounds/{id}", (main, params) => RT.views.roundDetail(main, params));
