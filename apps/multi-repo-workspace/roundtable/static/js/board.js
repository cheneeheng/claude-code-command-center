// #/board — repo cards grid fed by the shared 5s poll.
window.RT = window.RT || {};

RT.views = RT.views || {};

RT.views.board = function boardView(main) {
  const h = RT.h;
  main.replaceChildren(h("div", { class: "busy" }, "loading board…"));

  function card(p) {
    const head = h("h3", {}, p.name);
    if (p.sessions && p.sessions.streaming > 0) {
      head.append(h("span", { class: "pulse", title: "planning session streaming", "aria-label": "planning session streaming" }));
    }
    if (p.stub) head.append(h("span", { class: "stub-badge" }, "stub"));
    const el = h("div", {
      class: "card", role: "link", tabindex: "0",
      onclick: () => { location.hash = `#/repo/${encodeURIComponent(p.name)}`; },
      onkeydown: (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); el.click(); } },
    }, head);
    if (p.state) {
      const s = p.state;
      const bits = [];
      bits.push(`${s.detached ? "⌀ " : ""}${s.branch}`);
      if (s.dirty_count > 0) bits.push(`✚ ${s.dirty_count}`);
      if (s.ahead !== null && s.behind !== null) bits.push(`↑${s.ahead} ↓${s.behind}`);
      if (s.last_commit) bits.push(RT.fmt.ago(s.last_commit.ts));
      el.append(h("div", { class: "git-line" }, bits.map((b) => h("span", {}, b))));
    }
    if (p.git_error) {
      el.append(h("div", { class: "warn-strip" }, `git: ${p.git_error}`));
    }
    const chips = h("div", { class: "chips" });
    for (const status of ["ready", "running", "implemented"]) {
      const n = (p.plans && p.plans[status]) || 0;
      if (n > 0) chips.append(h("span", { class: `chip ${status}` }, `${n} ${status}`));
    }
    if (p.round && p.round.orders > 0) {
      const chip = h("span", { class: "chip state-queued" },
        `${p.round.orders} order${p.round.orders === 1 ? "" : "s"} this round`);
      if (p.round.running > 0) chip.prepend(h("span", { class: "pulse", "aria-hidden": "true" }), " ");
      chips.append(chip);
    }
    if (chips.childNodes.length) el.append(chips);
    return el;
  }

  function render(data) {
    const grid = h("div", { class: "board" }, data.projects.map(card));
    if (!data.projects.length) {
      main.replaceChildren(h("div", { class: "empty" },
        "no projects configured — create a .roundtable.json (roundtable init --scan ~/repos)"));
      return;
    }
    main.replaceChildren(grid);
  }

  const listener = (ev) => render(ev.detail);
  window.addEventListener("rt-board", listener);
  RT.viewCleanup = () => window.removeEventListener("rt-board", listener);
  if (RT.board.last) render(RT.board.last);
  else RT.pollBoard();
};

RT.router.register("#/board", (main) => RT.views.board(main));
