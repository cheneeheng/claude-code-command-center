# Vantage

Survey all your repos from one vantage point, diff any two files, and copy between them.

Vantage is a local, serverless repo explorer for when you've accumulated many unrelated Git
repos in one folder and can't get a usable overview from the filesystem or a web UI. Point it
at your projects root: every immediate subfolder becomes a card, sorted (by last activity, name,
or stack) and filterable by name. Expand a card to browse its file tree, pick one file from two
different repos to diff them in a slide-in sidebar, and copy/overwrite one onto the other. The
contributing repos stay highlighted on the board so you always know which pair is loaded. Each
expanded card can also open its repo in VSCode.

**Core flow: open → find two repos → compare a file → copy across.**

## Requirements

- A **Chromium-based browser** — Chrome, Edge, or Opera. It depends on the
  [File System Access API](https://developer.mozilla.org/docs/Web/API/File_System_API), which
  is **not** available in Firefox or Safari.
- No install, no build, no dependencies, no server. The app is a handful of static files
  (`index.html` + `styles/` + `scripts/`), loaded as classic stylesheets and scripts.

## Running

Open `index.html` directly in Chrome/Edge/Opera (double-click it, or use a `file://` URL).

1. Click **Change folder** and pick your projects root. The directory handle is saved in
   IndexedDB, so reopening the page reconnects without re-picking (the browser still requires
   one permission-grant click via **Reconnect folder**).
2. Filter the board by name and choose a sort order, then click a card's **▸** chevron to expand
   its file tree. (Clicking elsewhere on a card just highlights it as the focused one; the chevron
   is what expands it.)
3. Assign a file to side **A** and another (from any repo) to side **B**. A selection bar shows
   the current A/B (with **Swap** and **Clear**), and the contributing repo cards are
   highlighted. The diff sidebar slides in automatically once both sides are set. It can only be
   **open** or **minimized** (–) to a floating puck that re-opens it — there is no close; your
   selection is never lost by minimizing. To dismiss the comparison entirely, **Clear** it.
4. From the sidebar footer, **Copy A → B** or **Copy B → A** to overwrite the destination file
   (with a confirm step naming the exact target).

### Open in VSCode (optional)

Click **Set root path** and paste the absolute path of your projects root
(e.g. `/Users/you/projects` or `C:\Users\you\projects`). This enables the **Open in VSCode**
button on each expanded card. It's required separately because the File System Access API never
exposes the real filesystem path of the folder you pick — Vantage works fully without it.

## Notes and limitations

- **Reads and writes stay inside the folder you choose.** Copy/overwrite is the only
  destructive action, always confirmed; there is no delete.
- **Last-activity is a proxy**, derived from file modification times
  (`.git/logs/HEAD` → `.git/HEAD` → a shallow working-tree walk), not parsed Git history.
- Diffs are line-based (a hand-written LCS) and shown flat, not side-by-side.
- VSCode path composition assumes repos are **direct children** of the root.

## Development

There is nothing to build or install — edit the files in `styles/` or `scripts/` and refresh the
browser. The split is one concern per file, wired by classic `<link>`/`<script>` tags whose
**order in `index.html` is the dependency contract** (`scripts/namespace.js` first, `app.js`
last); cross-file sharing is via the `window.Vantage` namespace, not ES modules. The design and
constraints are documented in `docs/planning/` (the `*_v3` files are the current design) and
`CLAUDE.md`.
