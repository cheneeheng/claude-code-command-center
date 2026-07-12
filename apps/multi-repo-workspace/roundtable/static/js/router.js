// Hash router: pattern -> view. Unknown hash -> #/board.
window.RT = window.RT || {};

// Marks the top-nav link for the current section as active (nav rule: the
// active location must be visibly marked). Repo/session pages are reached
// from the board, so they mark "Board"; round-history detail marks "History".
RT.markActiveNav = function markActiveNav(hash) {
  const section = hash.startsWith("#/round") ? "#/round"
    : hash.startsWith("#/history") || hash.startsWith("#/rounds/") ? "#/history"
    : "#/board";
  document.querySelectorAll(".topnav a").forEach((a) => {
    a.classList.toggle("current", a.getAttribute("href") === section);
  });
};

RT.router = {
  routes: [],
  register(pattern, handler) {
    // pattern: e.g. "#/repo/{name}" or "#/repo/{name}/plan/{slug...}"
    // Placeholders become sentinels first (one pass, so names stay in pattern
    // order), then literals are regex-escaped, then sentinels become groups.
    const names = [];
    const rx = pattern
      .replace(/\{(\w+)(\.\.\.)?\}/g, (_, n, dots) => { names.push(n); return dots ? "\x01" : "\x02"; })
      .replace(/[.*+?^$()[\]\\]/g, (c) => "\\" + c)
      .replace(/\x01/g, "(.+)")
      .replace(/\x02/g, "([^/]+)");
    this.routes.push({ rx: new RegExp(`^${rx}$`), names, handler });
  },
  dispatch() {
    const hash = location.hash || "#/board";
    const main = document.getElementById("main");
    if (RT.viewCleanup) { RT.viewCleanup(); RT.viewCleanup = null; }
    RT.markActiveNav(hash);
    for (const route of this.routes) {
      const m = route.rx.exec(hash);
      if (m) {
        const params = {};
        route.names.forEach((n, i) => { params[n] = decodeURIComponent(m[i + 1]); });
        route.handler(main, params);
        return;
      }
    }
    location.hash = "#/board"; // unknown hash falls back to the board
  },
  start() {
    window.addEventListener("hashchange", () => this.dispatch());
    this.dispatch();
  },
};
