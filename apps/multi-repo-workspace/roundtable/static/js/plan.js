// #/repo/{name}/plan/{slug} — plan body (rendered md) + lifecycle history + actions.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.plan = async function planView(main, { name, slug }) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading plan…"));
  const plan = await RT.api.get(
    `/api/repos/${encodeURIComponent(name)}/plans/${slug}`);

  const actions = h("div", { class: "review-actions" });
  // Only the legal manual edge for the current status is shown — no disabled buttons.
  if (plan.status === "ready") {
    actions.append(h("button", {
      onclick: async () => {
        await RT.api.post(`/api/repos/${encodeURIComponent(name)}/plans/${slug}/status`, { to: "implemented" });
        RT.views.plan(main, { name, slug });
      },
    }, "Mark implemented"));
    if (RT.roundOpen()) {
      actions.append(h("button", { class: "btn-primary", onclick: () => RT.addToRound(name, slug) }, "Add to round"));
    }
  } else if (plan.status === "implemented") {
    actions.append(h("button", {
      onclick: async () => {
        await RT.api.post(`/api/repos/${encodeURIComponent(name)}/plans/${slug}/status`, { to: "ready" });
        RT.views.plan(main, { name, slug });
      },
    }, "Reopen"));
  }
  actions.append(h("button", {
    onclick: async (ev) => {
      await navigator.clipboard.writeText(plan.manual_command);
      ev.target.textContent = "Copied!";
      setTimeout(() => { ev.target.textContent = "Copy manual command"; }, 1500);
    },
  }, "Copy manual command"));

  const body = h("div", { class: "md-body" });
  RT.md.into(body, plan.body);

  const historyRows = (plan.history || []).map((rec) =>
    h("tr", {},
      h("td", { class: "dim" }, rec.ts),
      h("td", {}, `${rec.from} → ${rec.to}`),
      h("td", {}, rec.trigger)));

  main.replaceChildren(
    h("h2", {},
      h("a", { href: `#/repo/${encodeURIComponent(name)}` }, `◂ ${name}`),
      ` ${plan.title} `,
      h("span", { class: `chip ${plan.status}` }, plan.status)),
    actions,
    body,
    h("h3", {}, "Lifecycle history"),
    historyRows.length
      ? h("table", {},
          h("thead", {}, h("tr", {}, ["When", "Transition", "Trigger"].map((c) => h("th", {}, c)))),
          h("tbody", {}, historyRows))
      : h("div", { class: "empty" }, "no transitions yet"),
  );
};

RT.router.register("#/repo/{name}/plan/{slug...}", (main, params) => RT.views.plan(main, params));
