// #/repo/{name} — repo detail: tabs Plans · Files · History · Diff.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.addToRound = async function addToRound(project, slug) {
  await RT.api.post("/api/rounds/current/orders", { project, slug });
  RT.banner.hide();
  RT.pollBoard();
};

// Round-open + plan-ready gate for the Add-to-round affordance (family convention:
// controls appear only when functional).
RT.roundOpen = function roundOpen() {
  return RT.board.last && RT.board.last.round && RT.board.last.round.status === "open";
};

RT.views.repo = function repoView(main, { name }) {
  const h = RT.h;
  const tabs = ["Plans", "Sessions", "Files", "History", "Diff"];
  let active = sessionStorage.getItem(`rt-tab:${name}`) || "Plans";

  const tabbar = h("div", { class: "tabs", role: "tablist" });
  const panel = h("div", { role: "tabpanel" });
  main.replaceChildren(
    h("a", { class: "back-link", href: "#/board" }, "← Board"),
    h("h2", {}, name),
    tabbar, panel,
  );

  function renderTabs() {
    tabbar.replaceChildren(...tabs.map((t) =>
      h("button", {
        role: "tab",
        "aria-selected": String(t === active),
        onclick: () => { active = t; sessionStorage.setItem(`rt-tab:${name}`, t); renderTabs(); renderPanel(); },
      }, t)));
  }

  function renderPanel() {
    panel.replaceChildren(h("div", { class: "busy" }, `loading ${active.toLowerCase()}…`));
    ({ Plans: renderPlans, Sessions: renderSessions, Files: renderFiles, History: renderHistory, Diff: renderDiff })[active]();
  }

  // --- Plans tab -------------------------------------------------------------

  async function renderPlans() {
    const plansRes = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/plans`);
    const wrap = h("div", {});

    // Plan with Claude: inline prompt panel -> POST /api/sessions.
    const prefill = sessionStorage.getItem(`rt-prefill:${name}`) || "";
    sessionStorage.removeItem(`rt-prefill:${name}`);
    const promptBox = h("textarea", { rows: "3", placeholder: "What should we plan?" });
    promptBox.value = prefill;
    const planPanel = h("div", { hidden: prefill ? null : "" },
      promptBox,
      h("div", { class: "bar my-2" },
        h("button", {
          class: "btn-primary",
          onclick: async () => {
            const prompt = promptBox.value.trim();
            if (!prompt) return;
            const meta = await RT.api.post("/api/sessions", { project: name, prompt });
            location.hash = `#/session/${meta.id}`;
          },
        }, "Start planning session")));
    wrap.append(
      h("div", { class: "my-3" },
        h("button", { onclick: () => { planPanel.hidden = !planPanel.hidden; } }, "Plan with Claude")),
      planPanel,
    );

    if (!plansRes.plans.length) {
      wrap.append(h("div", { class: "empty" }, "no plans found in this repo's planning dir"));
    } else {
      wrap.append(h("table", {},
        h("thead", {}, h("tr", {}, ["Title", "Slug", "Status", "Updated", ""].map((c) => h("th", {}, c)))),
        h("tbody", {}, plansRes.plans.map((p) => {
          const actions = h("td", {});
          if (p.status === "ready" && RT.roundOpen()) {
            actions.append(h("button", { onclick: (ev) => { ev.stopPropagation(); RT.addToRound(name, p.slug); } }, "Add to round"));
          }
          return h("tr", {
            style: "cursor:pointer",
            onclick: () => { location.hash = `#/repo/${encodeURIComponent(name)}/plan/${p.slug}`; },
          },
            h("td", {}, p.title),
            h("td", {}, h("code", {}, p.slug)),
            h("td", {}, h("span", { class: `chip ${p.status}` }, p.status)),
            h("td", { class: "dim" }, RT.fmt.ago(p.mtime)),
            actions);
        }))));
    }
    panel.replaceChildren(wrap);
  }

  // --- Sessions tab ------------------------------------------------------------

  async function renderSessions() {
    const sessionsRes = await RT.api.get(`/api/sessions?project=${encodeURIComponent(name)}`);
    if (!sessionsRes.sessions.length) {
      panel.replaceChildren(h("div", { class: "empty" }, "no sessions yet"));
      return;
    }
    panel.replaceChildren(h("table", {},
      h("thead", {}, h("tr", {}, ["Status", "Turns", "Produced plans", "When"].map((c) => h("th", {}, c)))),
      h("tbody", {}, sessionsRes.sessions.map((s) =>
        h("tr", { style: "cursor:pointer", onclick: () => { location.hash = `#/session/${s.id}`; } },
          h("td", {}, s.status),
          h("td", {}, String(s.turns.length)),
          h("td", {}, s.produced_plans.map((p) => p.slug).join(", ") || "—"),
          h("td", { class: "dim" }, RT.fmt.agoIso(s.created_at)))))));
  }

  // --- Files tab --------------------------------------------------------------

  async function renderFiles() {
    const treePane = h("div", { class: "tree" });
    const filePane = h("div", { class: "file-pane" }, h("div", { class: "empty" }, "select a file"));
    const newPath = h("input", { type: "text", placeholder: "new file path (repo-relative)", class: "input-file-path" });
    const header = h("div", { class: "bar mb-2" },
      newPath,
      h("button", {
        onclick: () => {
          const rel = newPath.value.trim().replaceAll("\\", "/");
          if (rel) openEditor(rel, "", null);
        },
      }, "New file"));
    panel.replaceChildren(h("div", { class: "files-wrap" },
      h("div", { class: "tree-col" }, header, treePane), filePane));

    // rel -> tree button, so opening a file can highlight it in place of repeating
    // the filename in the (single) right-hand content column.
    const fileButtons = new Map();
    function selectInTree(rel) {
      for (const [r, btn] of fileButtons) btn.classList.toggle("selected", r === rel);
    }

    async function level(rel, depth, container) {
      const res = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/tree?path=${encodeURIComponent(rel)}`);
      for (const entry of res.entries) {
        const childRel = rel ? `${rel}/${entry.name}` : entry.name;
        const pad = `padding-left:${8 + depth * 14}px`;
        if (entry.is_dir) {
          let expanded = false;
          const kids = h("div", {});
          const btn = h("button", {
            style: pad, "aria-expanded": "false",
            onclick: async () => {
              expanded = !expanded;
              btn.setAttribute("aria-expanded", String(expanded));
              btn.firstChild.textContent = expanded ? "▾ " : "▸ ";
              if (expanded && !kids.childNodes.length) await level(childRel, depth + 1, kids);
              kids.hidden = !expanded;
            },
          }, h("span", {}, "▸ "), entry.name);
          container.append(btn, kids);
        } else {
          const btn = h("button", { style: pad, onclick: () => openFile(childRel) },
            entry.name, h("span", { class: "dim" }, ` ${entry.size}b`));
          fileButtons.set(childRel, btn);
          container.append(btn);
        }
      }
      if (!res.entries.length) container.append(h("div", { class: "dim pl-2" }, "(empty)"));
    }
    await level("", 0, treePane);

    // A pending open request (e.g. a plan link on the Round tab) lands here.
    const pending = sessionStorage.getItem(`rt-open:${name}`);
    if (pending) {
      sessionStorage.removeItem(`rt-open:${name}`);
      await openFile(pending);
    }

    async function openFile(rel) {
      selectInTree(rel);
      filePane.replaceChildren(h("div", { class: "busy" }, "loading…"));
      let res;
      try {
        res = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/file?path=${encodeURIComponent(rel)}`);
      } catch (err) {
        RT.banner.hide();
        const note = err.status === 415 ? "binary file — not viewable"
          : err.status === 413 ? "too large to view (512 KB cap)"
          : `cannot open: ${err.message}`;
        filePane.replaceChildren(h("div", { class: "empty" }, note));
        return;
      }
      showFile(rel, res.content, res.mtime);
    }

    function showFile(rel, content, mtime) {
      const isMd = rel.toLowerCase().endsWith(".md");
      const actionsBar = h("div", { class: "bar mb-2" },
        h("button", { onclick: () => openEditor(rel, content, mtime) }, "Edit"));
      const bodyWrap = h("div", {});
      if (isMd) {
        let rendered = true;
        const toggle = h("button", { onclick: () => { rendered = !rendered; toggle.textContent = rendered ? "Source" : "Rendered"; paint(); } }, "Source");
        actionsBar.append(toggle);
        const paint = () => {
          if (rendered) RT.md.intoWithFrontmatter(bodyWrap, content);
          else bodyWrap.replaceChildren(h("pre", {}, content));
        };
        paint();
      } else {
        bodyWrap.replaceChildren(h("pre", {}, content));
      }
      filePane.replaceChildren(actionsBar, bodyWrap);
    }

    function openEditor(rel, content, mtime) {
      const isMd = rel.toLowerCase().endsWith(".md");
      selectInTree(rel);
      let dirty = false;
      let currentMtime = mtime; // null => create on first save
      const ta = h("textarea", {});
      ta.value = content;
      const dirtyDot = h("span", { class: "dirty-dot", hidden: "" }, "● unsaved");
      ta.addEventListener("input", () => { dirty = true; dirtyDot.hidden = false; });

      const conflict = h("div", { class: "warn-strip", hidden: "" });
      async function save() {
        try {
          const res = await RT.api.put(
            `/api/repos/${encodeURIComponent(name)}/file?path=${encodeURIComponent(rel)}`,
            { content: ta.value, expect_mtime: currentMtime });
          currentMtime = res.mtime;
          dirty = false; dirtyDot.hidden = true; conflict.hidden = true;
          RT.banner.hide();
        } catch (err) {
          if (err.status === 409 && err.code === "stale_file") {
            RT.banner.hide();
            const diskMtime = err.payload.mtime;
            conflict.replaceChildren(
              "changed on disk — reload? Your edit stays in the editor until you decide. ",
              h("button", {
                onclick: async () => {
                  const fresh = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/file?path=${encodeURIComponent(rel)}`);
                  ta.value = fresh.content; currentMtime = fresh.mtime;
                  dirty = false; dirtyDot.hidden = true; conflict.hidden = true;
                },
              }, "Reload (discard my edit)"),
              " ",
              h("button", {
                onclick: () => { currentMtime = diskMtime; conflict.hidden = true; save(); },
              }, "Save anyway (overwrite)"));
            conflict.hidden = false;
          }
          // repo_busy and others stay in the shared banner
        }
      }
      ta.addEventListener("keydown", (ev) => {
        if ((ev.ctrlKey || ev.metaKey) && ev.key === "s") { ev.preventDefault(); save(); }
      });

      const bar = h("div", { class: "bar" },
        h("button", { class: "btn-primary", onclick: save }, "Save"),
        h("button", {
          onclick: () => {
            if (currentMtime === null && !dirty) { selectInTree(null); filePane.replaceChildren(h("div", { class: "empty" }, "select a file")); }
            else openFileAgain();
          },
        }, "Cancel"),
        dirtyDot);
      async function openFileAgain() { await openFile(rel); }

      const editorWrap = h("div", { class: "editor" }, conflict, bar, ta);
      if (isMd) {
        let showPreview = false;
        const preview = h("div", { hidden: "" });
        const tog = h("button", {
          onclick: () => {
            showPreview = !showPreview;
            tog.textContent = showPreview ? "Source" : "Rendered";
            preview.hidden = !showPreview; ta.hidden = showPreview;
            if (showPreview) RT.md.intoWithFrontmatter(preview, ta.value);
          },
        }, "Rendered");
        bar.append(tog);
        editorWrap.append(preview);
      }
      filePane.replaceChildren(editorWrap);
      ta.focus();
    }
  }

  // --- History tab ---------------------------------------------------------------

  async function renderHistory() {
    let res;
    try {
      res = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/log`);
    } catch (err) {
      RT.banner.hide();
      panel.replaceChildren(h("div", { class: "empty" }, `git error: ${err.message}`));
      return;
    }
    if (!res.commits.length) { panel.replaceChildren(h("div", { class: "empty" }, "no commits")); return; }
    panel.replaceChildren(h("table", {},
      h("thead", {}, h("tr", {}, ["Hash", "When", "Subject"].map((c) => h("th", {}, c)))),
      h("tbody", {}, res.commits.map((c) =>
        h("tr", {},
          h("td", {}, h("code", {}, c.hash.slice(0, 8))),
          h("td", { class: "dim" }, RT.fmt.ago(c.ts)),
          h("td", {}, c.subject))))));
  }

  // --- Diff tab --------------------------------------------------------------------

  async function renderDiff() {
    let res;
    try {
      res = await RT.api.get(`/api/repos/${encodeURIComponent(name)}/diff`);
    } catch (err) {
      RT.banner.hide();
      panel.replaceChildren(h("div", { class: "empty" }, `git error: ${err.message}`));
      return;
    }
    const wrap = h("div", {});
    if (!res.patch && !res.untracked.length) {
      wrap.append(h("div", { class: "empty" }, "working tree clean"));
    } else {
      if (res.stat) wrap.append(h("pre", { class: "mb-3" }, res.stat));
      if (res.truncated) wrap.append(h("div", { class: "warn-strip" }, "patch truncated at 1 MB"));
      if (res.patch) wrap.append(RT.diff.render(res.patch));
      if (res.untracked.length) {
        wrap.append(h("h3", { class: "mb-2 mt-3" }, "Untracked"),
          h("ul", {}, res.untracked.map((u) => h("li", {}, h("code", {}, u)))));
      }
    }
    panel.replaceChildren(wrap);
  }

  renderTabs();
  renderPanel();
};

RT.router.register("#/repo/{name}", (main, params) => RT.views.repo(main, params));
