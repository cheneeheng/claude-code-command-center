// #/round — the current round: orders, End Turn, live execution, review.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.round = async function roundView(main) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading round…"));
  const rnd = await RT.api.get("/api/rounds/current");

  // No page title: the global round dock above already carries the round's
  // identity, status, and cost.
  const wrap = h("div", {});

  if (rnd.status === "open") renderOpen();
  else if (rnd.status === "executing") renderExecuting();
  else if (rnd.status === "review") RT.views.reviewPanel(wrap, rnd);
  main.replaceChildren(wrap);

  // --- open ---------------------------------------------------------------------
  function renderOpen() {
    if (rnd.carried_followups.length) {
      const panel = h("div", { class: "carried" },
        h("h3", { style: "margin-top:0" }, `Carried from Round ${rnd.carried_followups[0].from_round}`));
      rnd.carried_followups.forEach((item, index) => {
        panel.append(h("div", { class: "review-actions" },
          h("span", {}, h("strong", {}, item.project), " · ", h("code", {}, item.slug), ` — ${item.note}`),
          h("button", {
            onclick: () => {
              sessionStorage.setItem(`rt-prefill:${item.project}`, item.note);
              sessionStorage.setItem(`rt-tab:${item.project}`, "Plans");
              location.hash = `#/repo/${encodeURIComponent(item.project)}`;
            },
          }, "Plan from this"),
          h("button", {
            onclick: async () => {
              await RT.api.post("/api/rounds/current/followups/dismiss", { index });
              RT.views.round(main);
            },
          }, "Dismiss")));
      });
      wrap.append(panel);
    }

    if (!rnd.orders.length) {
      wrap.append(h("div", { class: "empty" },
        "round has no orders — queue plans from a repo's Plans tab or a plan page"));
      return;
    }

    const rows = rnd.orders.map((o) => {
      const instr = h("textarea", {
        rows: "1",
        placeholder: "add instruction…",
        title: "optional — blank uses the project's instruction template",
        onchange: async (ev) => {
          await RT.api.post(`/api/orders/${o.id}/instruction`,
            { instruction: ev.target.value.trim() || null });
        },
      }, o.instruction || "");
      // Project opens the repo on its Plans tab; the plan opens the plan view directly.
      return h("tr", {},
        h("td", { class: "cell-project" }, RT.monogram(o.project), h("a", {
          href: `#/repo/${encodeURIComponent(o.project)}`, title: o.project,
          onclick: () => { sessionStorage.setItem(`rt-tab:${o.project}`, "Plans"); },
        }, o.project)),
        h("td", {}, h("a", {
          href: `#/repo/${encodeURIComponent(o.project)}/plan/${o.slug}`,
        }, h("code", {}, o.slug))),
        h("td", { class: "cell-instr" }, instr),
        h("td", { class: "cell-remove" }, h("button", {
          class: "btn-danger btn-sm remove-btn",
          onclick: async () => {
            await RT.api.del(`/api/rounds/current/orders/${o.id}`);
            RT.views.round(main);
          },
        }, RT.icon(RT.icons.trash), "Remove")));
    });
    // End Turn itself lives in the global round dock; this panel is the queue.
    wrap.append(
      h("span", { class: "eyebrow" }, `Queued orders · ${rnd.orders.length}`),
      h("p", { class: "panel-caption" },
        "when the turn ends, each order runs its plan headlessly in its repo"),
      h("div", { class: "card table-panel" },
        h("table", { class: "orders-table" },
          h("thead", {}, h("tr", {}, ["Project", "Plan", "Instruction", ""].map((c) => h("th", {}, c)))),
          h("tbody", {}, rows))));
  }

  // --- executing -------------------------------------------------------------------
  function renderExecuting() {
    wrap.append(h("button", {
      class: "btn-danger",
      onclick: async () => {
        await RT.api.post("/api/rounds/current/stop");
        RT.views.round(main);
      },
    }, "Stop round"));

    for (const o of rnd.orders) {
      const card = h("div", { class: "order-card" },
        h("div", { class: "head" },
          h("strong", {}, o.project), h("code", {}, o.slug),
          h("span", { class: `chip state-${o.state}` }, o.state),
          o.cost_est_usd !== null ? h("span", { class: "cost-chip" }, RT.fmt.costShort(o.cost_est_usd)) : null));
      const out = h("pre", { class: "out" });
      if (o.state === "running" || o.state === "queued") {
        card.append(out);
        RT.sse.open(`/api/orders/${o.id}/stream`, {
          onItem: (item) => { out.append(item.text + "\n"); out.scrollTop = out.scrollHeight; },
          onEnd: () => {},
          onError: () => {},
        });
      } else if (["succeeded", "failed", "stopped", "skipped"].includes(o.state)) {
        // Finished orders collapse to their tail lines.
        RT.api.get(`/api/orders/${o.id}/output`).then((res) => {
          out.append(res.lines.slice(-4).join("\n"));
          card.append(out);
        });
      }
      wrap.append(card);
    }

    // 3s state poll while executing (SKELETON freshness model). Cost display
    // lives in the round dock, refreshed by the board poll.
    const timer = setInterval(async () => {
      const fresh = await RT.api.get("/api/rounds/current");
      if (fresh.status !== "executing" ||
          JSON.stringify(fresh.orders.map((o) => o.state)) !== JSON.stringify(rnd.orders.map((o) => o.state))) {
        clearInterval(timer);
        RT.views.round(main);
      }
    }, 3000);
    RT.viewCleanup = () => clearInterval(timer);
  }
};

RT.router.register("#/round", (main) => RT.views.round(main));
