// Review panel — rendered inside #/round when the round is in review, and reused
// read-only by #/rounds/{id} for done rounds.
window.RT = window.RT || {};
RT.views = RT.views || {};

RT.views.reviewPanel = function reviewPanel(wrap, rnd, { readOnly = false } = {}) {
  const h = RT.h;
  const diffCache = {}; // one diff fetch per repo, shared across that repo's cards

  const byRepo = {};
  for (const o of rnd.orders) (byRepo[o.project] = byRepo[o.project] || []).push(o);

  const closeSlot = h("div", { style: "margin:14px 0" });

  function renderClose() {
    if (readOnly) return;
    closeSlot.replaceChildren();
    // Close Round renders only when every order is reviewed — the checkbox IS the
    // confirmation mechanism, so no extra confirm dialog.
    if (rnd.orders.length && rnd.orders.every((o) => o.reviewed)) {
      closeSlot.append(h("button", {
        class: "btn-primary",
        onclick: async () => {
          await RT.api.post("/api/rounds/current/close");
          RT.pollBoard();
          location.hash = "#/round";
          RT.views.round(document.getElementById("main"));
        },
      }, "Close Round"));
    } else {
      closeSlot.append(h("span", { class: "dim" }, "review every order to close the round"));
    }
  }

  for (const [repo, orders] of Object.entries(byRepo)) {
    for (const o of orders) {
      const card = h("div", { class: "order-card" });
      card.append(h("div", { class: "head" },
        h("strong", {}, repo), h("code", {}, o.slug),
        h("span", { class: `chip state-${o.state}` }, o.state),
        h("span", { class: "cost-chip" }, RT.fmt.cost(o.cost_est_usd, o.cost_reported_usd)),
        o.rc !== null ? h("span", { class: "dim" }, `rc=${o.rc}`) : null));

      // Output replay: collapsed, loads on expand.
      const replay = h("details", {}, h("summary", {}, "output replay"));
      let loaded = false;
      replay.addEventListener("toggle", async () => {
        if (replay.open && !loaded) {
          loaded = true;
          const res = await RT.api.get(`/api/orders/${o.id}/output`);
          replay.append(h("pre", { class: "out" }, res.lines.join("\n") || "(no output)"));
        }
      });
      card.append(replay);

      if (!readOnly) {
        // Repo diff: fetched once per repo, shared across that repo's cards.
        const diffDetails = h("details", {}, h("summary", {}, `working-tree diff (${repo})`));
        let diffLoaded = false;
        diffDetails.addEventListener("toggle", async () => {
          if (diffDetails.open && !diffLoaded) {
            diffLoaded = true;
            diffCache[repo] = diffCache[repo] || RT.api.get(`/api/repos/${encodeURIComponent(repo)}/diff`);
            const d = await diffCache[repo];
            diffDetails.append(h("pre", { class: "out" }, d.patch || "(clean)"),
              d.untracked.length ? h("div", { class: "dim" }, `untracked: ${d.untracked.join(", ")}`) : "");
          }
        });
        card.append(diffDetails);

        const reviewed = h("input", { type: "checkbox", id: `rv-${o.id}` });
        reviewed.checked = o.reviewed;
        reviewed.addEventListener("change", async () => {
          await RT.api.post(`/api/orders/${o.id}/reviewed`, { reviewed: reviewed.checked });
          o.reviewed = reviewed.checked;
          renderClose();
        });
        const note = h("input", { type: "text", placeholder: "follow-up note (carried to the next round)" });
        note.value = o.followup || "";
        note.addEventListener("blur", async () => {
          await RT.api.post(`/api/orders/${o.id}/followup`, { note: note.value });
        });
        card.append(h("div", { class: "review-actions" },
          h("label", { for: `rv-${o.id}` }, reviewed, " Reviewed"),
          note));
      } else {
        card.append(h("div", { class: "review-actions dim" },
          o.reviewed ? "reviewed ✓" : "not reviewed",
          o.followup ? h("span", {}, ` · follow-up: ${o.followup}`) : null));
      }
      wrap.append(card);
    }

    if (!readOnly) {
      // Per-repo commit box (the app's only git write).
      const msg = h("input", { type: "text", placeholder: `commit message for ${repo}` });
      const result = h("span", { class: "dim" });
      wrap.append(h("div", { class: "commit-box" },
        msg,
        h("button", {
          onclick: async () => {
            try {
              const res = await RT.api.post(`/api/repos/${encodeURIComponent(repo)}/commit`, { message: msg.value });
              RT.banner.hide();
              result.textContent = `committed ${res.head.slice(0, 8)}: ${res.subject}`;
            } catch (err) {
              RT.banner.hide();
              result.textContent = err.code === "nothing_to_commit" ? "nothing to commit"
                : err.code === "repo_busy" ? "repo busy — try after the run finishes"
                : `commit failed: ${err.message}`;
            }
          },
        }, `Commit ${repo}`),
        result));
    }
  }

  if (!rnd.orders.length) wrap.append(h("div", { class: "empty" }, "round has no orders"));
  wrap.append(closeSlot);
  renderClose();
};
