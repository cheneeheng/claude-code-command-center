// ---- state ----
// Loaded first: classic scripts share the global scope, so these bindings are
// visible to (and mutated by) every later file. acquireVsCodeApi() may only be
// called once per webview, so the handle lives here.
const vscodeApi = acquireVsCodeApi();
const SCOPES = ["local", "project", "user"];
const SCOPE_LABELS = { local: "Local", project: "Project", user: "User" };
let state = { local: [], project: [], user: [] };
let installedScopesMap = {};
let marketplaces = [];
let installPanelOpen = false;
let selectedMarketplace = null;
let operationInProgress = false;
// Tracks the element bundle + labels for the in-flight streamed op, keyed by id,
// so install/uninstall messages (which carry only id) update the right elements.
const pendingOps = {};
