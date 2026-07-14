// Boot: router + the 5s board poll loop feeding the header round bar and any
// view that listens for "rt-board" (SKELETON freshness model: poll, not SSE).
window.RT = window.RT || {};

RT.board = { last: null };

RT.pollBoard = async function pollBoard() {
  try {
    const data = await RT.api.get("/api/board");
    RT.board.last = data;
    RT.renderRoundBar(data);
    window.dispatchEvent(new CustomEvent("rt-board", { detail: data }));
  } catch { /* the banner already reported it */ }
};

RT.ROUND_STAGES = ["open", "executing", "review", "done"];

RT.renderRoundBar = function renderRoundBar(data) {
  const h = RT.h;
  const dock = document.getElementById("rounddock");
  dock.replaceChildren();
  const rnd = data.round;
  dock.hidden = !rnd && !data.last_done;
  const left = h("div", { class: "dock-left" });
  const center = h("div", { class: "dock-center" });
  if (rnd) {
    left.append(
      h("span", { class: "eyebrow" }, "Current round"),
      h("div", { class: "round-line" },
        h("span", { class: "round-title" }, `Round ${rnd.number}`),
        h("a", { class: "orders-chip", href: "#/round" },
          `${rnd.orders} order${rnd.orders === 1 ? "" : "s"}`),
        h("span", { class: "cost-chip", title: "estimated round cost so far" },
          RT.fmt.costShort(rnd.cost_est_usd))));
    // Lifecycle flow track: filled through the current node, ghosted beyond.
    const idx = RT.ROUND_STAGES.indexOf(rnd.status);
    const flow = h("div", { class: "flow", role: "img",
      "aria-label": `Round status: ${rnd.status}` });
    RT.ROUND_STAGES.forEach((s, i) => {
      flow.append(h("span", {
        class: "flow-step" + (i < idx ? " past" : i === idx ? ` current st-${s}` : ""),
        "aria-hidden": "true",
      }, h("span", { class: "flow-node" }), h("span", { class: "flow-label" }, s)));
    });
    left.append(flow);
    if (rnd.status === "executing") {
      center.append(h("span", { class: "dim" },
        h("span", { class: "dot dot-live", "aria-hidden": "true" }),
        ` executing ${rnd.terminal}/${rnd.orders}…`));
    } else if (rnd.status === "open" && rnd.orders > 0) {
      center.append(
        h("button", {
          class: "btn-endturn",
          onclick: async (ev) => {
            ev.preventDefault();
            await RT.api.post("/api/rounds/current/end-turn");
            location.hash = "#/round";
            RT.pollBoard();
          },
        }, h("span", { class: "glyph", "aria-hidden": "true" }, "↻"), "End Turn"),
        h("span", { class: "dock-caption" },
          `runs the ${rnd.orders} queued order${rnd.orders === 1 ? "" : "s"}`));
    } else if (rnd.status === "review") {
      center.append(
        h("a", { class: "btn btn-outline", href: "#/round" }, "Review round"),
        h("span", { class: "dock-caption" }, "inspect results and commit"));
    }
  }
  const right = h("div", { class: "dock-right" });
  if (data.last_done) {
    const d = data.last_done;
    // Mini scoreboard mirroring the left block's anatomy; the whole panel is a
    // quiet link into History.
    const stat = (val, lbl, cls) => h("span", { class: "stat" },
      h("span", { class: `stat-value ${cls}` }, val),
      h("span", { class: "stat-label" }, lbl));
    right.append(h("a", { class: "lastround", href: "#/history", title: "View round history" },
      h("span", { class: "eyebrow" }, "Last round"),
      h("div", { class: "scoreboard" },
        stat(`${d.succeeded}`, "succeeded", "text-success"),
        d.failed > 0 ? stat(`${d.failed}`, "failed", "text-danger") : null,
        stat(RT.fmt.costShort(d.cost_est_usd), "est. cost", "dim"))));
  }
  dock.append(left, center, right);
};

document.addEventListener("DOMContentLoaded", () => {
  RT.router.start();
  RT.pollBoard();
  setInterval(RT.pollBoard, 5000);
});
