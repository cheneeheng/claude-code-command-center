---
artifact: ITER_05
status: ready
created: 2026-05-15
scope: Housekeeping — CSS build sync, Windows path hardening, animated expand/collapse for skill/agent disclosures
sections_changed: [03, 04, 05]
sections_unchanged: [01, 02]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture
> Unchanged — see ITER_04.md §02

---

## §03 · Tech Stack

No new runtime dependencies.

**New build tooling:**
- `make` — used only for the `sync-css` target. `make` is available on macOS and Linux by default. On Windows: either install `make` via Chocolatey/Scoop, or run the PowerShell fallback script `scripts/sync-css.ps1` directly. The VSCode extension's `package.json` wires this into a `prepackage` script so `vsce package` always syncs CSS first.

No other stack changes.

---

## §04 · Backend

### `styles.css` sync — Makefile approach

**Problem:** `html/styles.css` and `vscode-extension/webview/styles.css` are kept in sync manually. The VSCode copy must live inside `vscode-extension/webview/` to be served via `asWebviewUri`. A symlink across directories is fragile on Windows and inside `.vsix` packages.

**Solution:** A `Makefile` at the repo root with a single `sync-css` target that copies the canonical source to the webview directory. The canonical source is `html/styles.css`. The `vscode-extension/webview/styles.css` file becomes a **generated file** — never edit it directly.

```
project root/
├── Makefile
├── scripts/
│   └── sync-css.ps1          ← Windows fallback (no make required)
├── html/
│   ├── styles.css            ← canonical source — edit this one
│   └── ...
└── vscode-extension/
    └── webview/
        └── styles.css        ← generated — do not edit
```

**`Makefile`:**
```makefile
.PHONY: sync-css

# Copy canonical CSS from html/ into the VSCode webview directory.
# Run this after any change to html/styles.css.
sync-css:
	cp html/styles.css vscode-extension/webview/styles.css
	@echo "styles.css synced → vscode-extension/webview/styles.css"
```

**`scripts/sync-css.ps1`** (Windows fallback):
```powershell
Copy-Item -Path "html\styles.css" -Destination "vscode-extension\webview\styles.css" -Force
Write-Host "styles.css synced -> vscode-extension\webview\styles.css"
```

**`vscode-extension/package.json` — wire into packaging:**
```json
{
  "scripts": {
    "prepackage": "make sync-css || powershell -ExecutionPolicy Bypass -File ../scripts/sync-css.ps1"
  }
}
```

> The `||` fallback means `make` is tried first; if it fails (Windows without make installed), the PowerShell script runs instead. Either way, CSS is synced before `vsce package` produces the `.vsix`.

**`.gitignore` note:** Do NOT add `vscode-extension/webview/styles.css` to `.gitignore`. It should be committed so the extension works without running `make sync-css` after a fresh clone. The `Makefile` is for keeping it up to date during development.

---

### Windows path normalisation hardening

**Problem (from ITER_03 deferred):** `pathlib.Path.resolve()` and `path.resolve()` handle most cases, but two edge cases on Windows can cause plugin project matching to fail silently:
1. **Drive-letter case**: `C:\Users\...` vs `c:\Users\...` — Windows FS is case-insensitive but Python and Node may not normalise the drive letter consistently.
2. **Trailing separators**: `C:\project\` vs `C:\project` — `resolve()` strips these, but only if the path actually exists on disk at resolve time.

**Fix — Python (`server.py`):**

Replace all bare `str(pathlib.Path(p).resolve())` comparisons with a helper:

```python
def normalise_path(p: str) -> str:
    """
    Normalise a filesystem path for reliable comparison across platforms.
    On Windows: lowercases the drive letter and resolves separators.
    On all platforms: resolves symlinks, removes trailing slashes.
    Returns empty string for empty/None input.
    """
    if not p:
        return ""
    try:
        resolved = pathlib.Path(p).resolve()
        s = str(resolved)
        # Windows only: lowercase drive letter to normalise "C:\..." vs "c:\..."
        if len(s) >= 2 and s[1] == ":":
            s = s[0].lower() + s[1:]
        return s
    except Exception:
        return str(p)  # fall back to raw string if resolve fails (path doesn't exist)
```

Replace every `str(pathlib.Path(x).resolve())` call in `load_installed_plugins()` with `normalise_path(x)`.

**Fix — Node.js (`extension.js`):**

```js
function normalisePath(p) {
  if (!p) return '';
  try {
    const resolved = path.resolve(p);
    // Windows: lowercase drive letter
    if (/^[A-Z]:/.test(resolved)) {
      return resolved[0].toLowerCase() + resolved.slice(1);
    }
    return resolved;
  } catch {
    return p;
  }
}
```

Replace every `path.resolve(x)` comparison in `loadInstalledPlugins()` with `normalisePath(x)`.

**UNC paths** (`\\server\share\...`): `pathlib.Path.resolve()` and `path.resolve()` handle UNC paths correctly on modern Python 3.6+ and Node 12+. No special handling needed beyond what the helpers above already provide. Add a comment in each helper noting UNC paths are handled by the platform resolver.

---

## §05 · Frontend

### Animated expand/collapse for skills and agents disclosures

**Problem (from ITER_02 deferred):** The current `display: none` / `display: block` toggle is abrupt. A `max-height` CSS transition gives a smooth open/close without JavaScript animation libraries.

**Approach:** `max-height` transition. The list gets a `max-height: 0` when collapsed and a large `max-height` when expanded. The browser interpolates between them. `overflow: hidden` clips content during the transition.

**CSS changes** — replace the existing `.skills-list` rules in `html/styles.css` (then run `make sync-css`):

```css
/* Replace the existing .skills-list block */
.skills-list {
  max-height: 0;
  overflow: hidden;
  margin-top: 0;
  padding-left: 12px;
  border-left: 2px solid transparent;
  transition:
    max-height 200ms ease-out,
    margin-top 200ms ease-out,
    border-color 200ms ease-out;
}

.skills-list.is-open {
  max-height: 600px;   /* large enough to never clip real content; adjust if plugins have many skills */
  margin-top: 6px;
  border-left-color: var(--border);
}
```

> **Why 600px?** `max-height` must be a fixed value for the transition to work — `max-height: none` cannot be transitioned. 600px comfortably fits ~20 skill/agent rows. If a plugin ever has significantly more, the list will still expand correctly (just without animation past 600px). This is an acceptable trade-off; a ResizeObserver-based JS approach can replace it later if needed.

**JS changes — `toggleSkills(btn)`:** No logic changes required. The function already toggles `is-open` on the list element. The CSS transition activates automatically.

**Remove the old `display: none` / `display: block` rules** — the new `max-height: 0` / `max-height: 600px` pair replaces them entirely. Do not leave both in the file.

**VSCode webview:** run `make sync-css` after the CSS edit. No JS changes in `panel.html`.

---

## Deferred

- Plugin metadata (description, icon) — deferred until plugin manifest format is defined.
- `.vsix` packaging — see ITER_08.
- File watching — see ITER_06.
- Install progress streaming — see ITER_07.
- Marketplace refresh — see ITER_08.
