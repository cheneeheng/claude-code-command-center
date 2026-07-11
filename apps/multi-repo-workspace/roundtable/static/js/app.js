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

RT.renderRoundBar = function renderRoundBar(data) {
  const h = RT.h;
  const bar = document.getElementById("roundbar");
  bar.replaceChildren();
  const rnd = data.round;
  if (!rnd) return;
  const label = `Round ${rnd.number} · ${rnd.status} · ${rnd.orders} order${rnd.orders === 1 ? "" : "s"}`;
  const link = h("a", { class: "round-link", href: "#/round" }, label);
  bar.append(link);
  if (rnd.status === "executing") {
    bar.append(h("span", { class: "dim" },
      h("span", { class: "pulse", "aria-hidden": "true" }), ` executing ${rnd.terminal}/${rnd.orders}…`));
  } else if (rnd.status === "open" && rnd.orders > 0) {
    bar.append(h("button", {
      class: "primary",
      onclick: async (ev) => {
        ev.preventDefault();
        await RT.api.post("/api/rounds/current/end-turn");
        location.hash = "#/round";
        RT.pollBoard();
      },
    }, "End Turn"));
  }
  if (data.last_done) {
    const d = data.last_done;
    bar.append(h("span", { class: "last-done" },
      `last round: ${d.succeeded} ✓ ${d.failed} ✗ · ${RT.fmt.costShort(d.cost_est_usd)}`));
  }
};

document.addEventListener("DOMContentLoaded", () => {
  RT.router.start();
  RT.pollBoard();
  setInterval(RT.pollBoard, 5000);
});
