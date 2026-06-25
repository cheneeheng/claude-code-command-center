---
artifact: ITER_17
status: ready
created: 2026-06-06
scope: Per-scope install/uninstall matrix — a plugin can be installed at several scopes at once. Marketplace offers install at any not-yet-installed scope (no longer flips to a single Uninstall); per-scope uninstall moves into the Local/Project/User section rows.
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13, ITER_14, ITER_15, ITER_16]
---

# ITER_17 · Per-scope install/uninstall matrix

> The optional boundary deferred from ITER_15: because `installed_plugins.json` holds an array of entries per plugin, the same plugin can be installed at Local, Project, and User simultaneously. This iteration makes install and uninstall per-scope. The scoped endpoints already exist (`install-stream` scope from ITER_15, `uninstall-stream` scope from ITER_12) — this is mostly a UI rework plus two small backend fixes.

## §01 · Concept
> Unchanged — see ITER_13 § 01.

---

## §02 · Architecture

### Division of surfaces (revised)

- **Sections (Local / Project / User)** become the per-scope management surface: a row already shows its scope's state and (ITER_14) toggle and (ITER_15) Install when not installed. This iteration adds **Uninstall** to installed section rows, scoped to that section.
- **Marketplace panel** becomes install-only and scope-aware: it offers install at any scope the plugin is **not yet** installed at, and shows the scopes it already is. It no longer flips to a single Uninstall once installed somewhere — **supersedes the ITER_12 union Install/Uninstall toggle.** Uninstall now lives in the sections.

### `uninstall-stream` scope domain — fix

`POST /api/uninstall-stream` (ITER_12 §02) validated `scope` as `"local" | "global"`. The model moved to three scopes in ITER_13, so this is updated to `"local" | "project" | "user"`. Request/response shapes are otherwise unchanged.

### Marketplace annotation — per-scope

The marketplace annotation built in `_refresh` / the marketplace payload (ITER_13 §04 unioned installed ids into one set) is replaced by a per-id **installed-scopes map**:

```json
{ "installedScopes": { "ceh-dev-tools@ceh-plugins": ["local", "user"] } }
```

The frontend uses this to decide, per scope, whether to show an "installed" tag or an install control.

---

## §03 · Tech Stack
> Unchanged — see SKELETON § 03.

---

## §04 · Backend

### HTML version — `server.py`

**`/api/uninstall-stream` scope validation** — widen to three scopes:

```python
if scope not in ("local", "project", "user"):     # was ("local", "global")
    self._respond_json({"ok": False, "error": "scope must be local, project, or user"}, status=400); return
```

**Per-scope installed annotation.** Replace the union `installedIds` set with an `installedScopes` map built from the three sections, and include it in the `/api/plugins` (or marketplace) payload the frontend already consumes:

```python
installed_scopes = {}
for scope in ("local", "project", "user"):
    for p in sections[scope]:
        if p["installed"]:
            installed_scopes.setdefault(p["id"], []).append(scope)
payload["installedScopes"] = installed_scopes
```

`install-stream` is unchanged (already scope-aware, ITER_15 §04).

### VSCode extension — `extension.js`

- `streamUninstall` already takes `scope` (ITER_12 §04); update its **caller/validation** to allow `project` and `user` (the ITER_12 confirmation/handler assumed local/global). The modal confirmation wording should name the scope, as the toggle does (ITER_14 §04).
- Build the same `installedScopes` map in `_refresh` (mirror of the Python annotation) and post it to the webview in the `load` message.

---

## §05 · Frontend

### Marketplace row — per-scope install (replaces ITER_12 toggle)

Using `installedScopes[id]` (default `[]`):

- For each scope **not** in `installedScopes[id]`, it is installable; for each scope **in** it, show a small read-only "Installed · Local/Project/User" tag.
- Render the scope `<select>` (ITER_15 §05) populated with **only the not-yet-installed scopes**; the Install button installs at the selected scope. If all three are installed, hide the select/button and show only the tags.
- Remove the installed → Uninstall flip from the marketplace row (ITER_12 §05). `installPlugin(id, scope, els)` (ITER_15) is reused unchanged.

> A plugin installed at Local and then installed at User ends up with both tags; each scope's row in the sections reflects its own state on refresh.

### Section rows — per-scope uninstall

For installed section rows (`installed: true`), add an **Uninstall** button next to the toggle, scoped to the row's section:

```html
<button class="mp-install-btn mp-install-btn--uninstall"
        id="btn-uninstall-${scope}-${CSS.escape(id)}"
        onclick="uninstallPlugin('${escapeHtml(id)}','${scope}', sectionEls('${scope}','${escapeHtml(id)}'))">
  Uninstall
</button>
```

- `uninstallPlugin(id, scope, els)` is the existing function (ITER_12 §05), already scope-aware; generalize its element lookup to take `els` the same way `installPlugin` did in ITER_15 §05.
- Section rows must expose the scope-qualified `log-/err-${scope}-${id}` elements for **both** install (ITER_15) and uninstall streaming — ensure they are present on installed rows too, not only `installed: false` rows.
- On success, refresh: the row flips to `installed: false` (and, if it has no settings entry in that scope, drops out of the section entirely per ITER_13's membership rule).

> Uninstall here removes only this scope's install entry; entries at other scopes are untouched. This is the matrix in action.

---

## Deferred

- **Bulk / cross-scope "promote" actions** (e.g. move an install from Project to User in one step) — out of scope; install-at-new-scope then uninstall-old-scope achieves it manually.
- **Smoke-test coverage** of multi-scope install/uninstall (extends ITER_11) — recommended follow-up.
