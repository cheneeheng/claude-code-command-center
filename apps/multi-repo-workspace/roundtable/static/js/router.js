// Hash router: pattern -> view. Unknown hash -> #/board.
window.RT = window.RT || {};

RT.router = {
  routes: [],
  register(pattern, handler) {
    // pattern: e.g. "#/repo/{name}" or "#/repo/{name}/plan/{slug...}"
    const names = [];
    const rx = pattern
      .replace(/[.*+?^$()[\]\\]/g, (c) => "\\" + c)
      .replace(/\{(\w+)\.\.\.\}/g, (_, n) => { names.push(n); return "(.+)"; })
      .replace(/\{(\w+)\}/g, (_, n) => { names.push(n); return "([^/]+)"; });
    this.routes.push({ rx: new RegExp(`^${rx}$`), names, handler });
  },
  dispatch() {
    const hash = location.hash || "#/board";
    const main = document.getElementById("main");
    if (RT.viewCleanup) { RT.viewCleanup(); RT.viewCleanup = null; }
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
