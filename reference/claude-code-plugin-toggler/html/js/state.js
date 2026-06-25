// ---- state ----
// Loaded first: classic scripts share the global scope, so these bindings are
// visible to (and mutated by) every later file.
const SCOPES = ["local", "project", "user"];
const SCOPE_LABELS = { local: "Local", project: "Project", user: "User" };
let state = { local: [], project: [], user: [] };
let installedScopesMap = {};   // { id: ["local", "user"] } from /api/plugins (ITER_17)
let marketplaces = [];
let installPanelOpen = false;
let selectedMarketplace = null;
let operationInProgress = false;
