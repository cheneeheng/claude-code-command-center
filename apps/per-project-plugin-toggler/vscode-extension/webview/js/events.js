// ---- delegated event wiring ----
// The content security policy refuses inline handlers, so every action in generated HTML
// is a data-action attribute, run from these listeners on document. Rows re-rendered
// through innerHTML need no re-binding. Plugin ids arrive through data-id, which the
// browser decodes back to the raw id.
const ACTIONS = {
  "open-install-panel": { on: "click", run: () => openInstallPanel() },
  "marketplace-refresh": { on: "click", run: () => triggerMarketplaceRefresh() },
  "close-install-panel": { on: "click", run: () => closeInstallPanel() },
  "select-marketplace": {
    on: "change",
    run: (el) => {
      selectedMarketplace = el.value;
      mpSearch = "";
      renderInstallPanel();
    },
  },
  "search-marketplace": {
    on: "input",
    run: (el) => {
      mpSearch = el.value;
      applyMpSearch();
    },
  },
  "mp-install": {
    on: "click",
    run: (el) => installPlugin(el.dataset.id, mpScopeVal(el.dataset.id), mpEls(el.dataset.id)),
  },
  "toggle-disclosure": { on: "click", run: (el) => toggleDisclosure(el) },
  uninstall: {
    on: "click",
    run: (el) =>
      uninstallPlugin(el.dataset.id, el.dataset.scope, sectionUninstallEls(el.dataset.scope, el.dataset.id)),
  },
  install: {
    on: "click",
    run: (el) =>
      installPlugin(el.dataset.id, el.dataset.scope, sectionInstallEls(el.dataset.scope, el.dataset.id)),
  },
};

for (const type of ["click", "change", "input"]) {
  document.addEventListener(type, (event) => {
    const el = event.target.closest("[data-action]");
    const action = el && Object.hasOwn(ACTIONS, el.dataset.action) && ACTIONS[el.dataset.action];
    if (action && action.on === type) action.run(el);
  });
}
