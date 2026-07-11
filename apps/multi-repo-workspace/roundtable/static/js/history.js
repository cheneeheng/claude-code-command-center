// #/history — rounds table; #/rounds/{id} — read-only past round detail.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.history = async function historyView(main) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading history…"));
  const res = await RT.api.get("/api/rounds");
  if (!res.rounds.length) {
    main.replaceChildren(h("h2", {}, "Rounds"), h("div", { class: "empty" }, "no rounds yet"));
    return;
  }
  const rows = res.rounds.map((r) => {
    const counts = { succeeded: 0, failed: 0, skipped: 0 };
    for (const o of r.orders) {
      if (o.state === "succeeded") counts.succeeded += 1;
      else if (o.state === "failed" || o.state === "stopped") counts.failed += 1;
      else if (o.state === "skipped") counts.skipped += 1;
    }
    return h("tr", { style: "cursor:pointer", onclick: () => { location.hash = `#/rounds/${r.id}`; } },
      h("td", {}, String(r.number)),
      h("td", {}, h("span", { class: "chip state-queued" }, r.status)),
      h("td", {}, String(r.orders.length)),
      h("td", {}, `${counts.succeeded} ✓ / ${counts.failed} ✗ / ${counts.skipped} –`),
      h("td", {}, RT.fmt.costShort(r.cost_est_usd)),
      h("td", { class: "dim" }, RT.fmt.agoIso(r.executed_at)),
      h("td", { class: "dim" }, RT.fmt.agoIso(r.closed_at)));
  });
  main.replaceChildren(
    h("h2", {}, "Rounds"),
    h("table", {},
      h("thead", {}, h("tr", {},
        ["#", "Status", "Orders", "Outcomes", "Cost", "Executed", "Closed"].map((c) => h("th", {}, c)))),
      h("tbody", {}, rows)));
};

RT.views.roundDetail = async function roundDetailView(main, { id }) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading round…"));
  const rnd = await RT.api.get(`/api/rounds/${encodeURIComponent(id)}`);
  const wrap = h("div", {},
    h("h2", {},
      h("a", { href: "#/history" }, "◂ history"),
      ` Round ${rnd.number} `,
      h("span", { class: "chip state-queued" }, rnd.status),
      " ", h("span", { class: "cost-chip" }, `round cost: ${RT.fmt.costShort(rnd.cost_est_usd)}`)));
  // Read-only reuse of the review card layout: recorded flags/notes/costs, replay.
  RT.views.reviewPanel(wrap, rnd, { readOnly: rnd.status === "done" });
  main.replaceChildren(wrap);
};

RT.router.register("#/history", (main) => RT.views.history(main));
RT.router.register("#/rounds/{id}", (main, params) => RT.views.roundDetail(main, params));
