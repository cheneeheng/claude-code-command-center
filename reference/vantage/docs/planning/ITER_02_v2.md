---
artifact: ITER_02_v2
status: ready
created: 2026-06-14
scope: Add an Open in VSCode button to each expanded card, gated on a one-time optional root-path entry stored in IndexedDB
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v2, ITER_01_v2]
mvp: true
mvp_target: A single brand-styled index.html that browses many repos, diffs two files in a slide-in closeable/minimizable sidebar (selection persists), with jump-to-repo search removed and an Open-in-VSCode button on each expanded card
---

# Vantage v2 — ITER_02: Open in VSCode (MVP terminator)

> §01 Concept — Unchanged — see SKELETON_v2 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v2 § 03

---

## §02 · Architecture (changes only)

This iteration turns the **Editor** module and the **Persist** root-path functions from
stub to working. No new in-memory entities; one persisted field gains a writer/reader.

- **Persist.`saveRootPath(str)` / `loadRootPath() → string | null`** — store and read an
  optional absolute path for the projects root in IndexedDB, alongside the existing
  directory handle and scan cache.
- **Editor.`vscodeUri(repoName) → string`** — composes `vscode://file/<rootPath>/<repoName>`.
  Returns `null` when `rootPath` is unset, which keeps the button disabled.

### Why a separate root-path entry exists (the core constraint)

The File System Access API deliberately **does not expose the absolute filesystem path**
of the folder chosen via `showDirectoryPicker()` — the page gets an opaque handle plus
the folder `name`, never `/Users/.../projects`. So the path used for the VSCode link
**cannot be derived** from the picked folder; it must be supplied separately. The
"Change folder" picker (handle, no path) and the root-path entry (path, no handle) are
two different things that cannot be merged — this is by design in the API, not a gap we
can close.

Resolution: the root-path entry is a **separate, optional, manual text field**. Vantage
works fully without it; only the VSCode buttons depend on it.

---

## §05 · Frontend (changes only)

### Root-path entry

A small settings affordance in the brand header (e.g. a "Set root path" control) opens a
text input where the user types/pastes the absolute path of the projects root once
(e.g. `/Users/eeheng/projects`). On save it is written via `Persist.saveRootPath` and
loaded on every subsequent open. The field is optional and clearly labelled as needed
only for opening repos in VSCode.

### Open in VSCode button (stub → real)

On each **ExpandedCard**, the button:
- is **disabled** (with tooltip "Set root path to enable") while `loadRootPath()` is null;
- once a root path exists, becomes an anchor whose `href` is
  `Editor.vscodeUri(repo.name)` → `vscode://file/<rootPath>/<repo.name>`.

Clicking hands the `vscode://` URL to the OS, which routes it to VSCode (installed VSCode
registers this protocol handler). The first click typically triggers a one-time browser
prompt ("Open Visual Studio Code?"). No server, no shell-out — just an anchor.

### Convention for the disabled control

Per the skeleton's stub strategy, the button is **rendered but disabled** until its
prerequisite (root path) is set — it is never hidden — so the capability is discoverable
and the tooltip explains how to enable it.

### Build-time notes (address proactively)

- **Editor is hardcoded to VSCode** for v2 (`vscode://`). Editor-agnostic support is out
  of scope (see below).
- **Verify the `vscode://file/` path/slash format at build time** — it differs slightly
  across OSes (notably Windows drive letters and leading slashes). Compose accordingly.
- The simple `rootPath + "/" + repo.name` composition assumes repos are **direct
  children** of the root, which is Vantage's model. Nested repos would break it — also
  out of scope below.

### How to run locally

Unchanged — open `index.html` in Chrome/Edge. To exercise: set the root path once →
expand a card → click **Open in VSCode** → confirm the repo opens (accept the one-time
browser prompt on first use).

---

## Out of MVP scope

- Editor-agnostic open (Cursor `cursor://`, JetBrains, etc.) — VSCode hardcoded for now.
- Auto-deriving the root path from the picked handle — impossible per the FSA API; manual
  entry stands.
- Nested-repo support for VSCode path composition — model is direct children only.
- Syntax-highlighted or side-by-side (vs. flat line-by-line) diffs.
- Embedding/offline-bundling brand fonts if the brand sheet references CDN assets —
  handle only if going fully offline is required.
- Any change beyond the four v2 items (brand CSS, slide-in sidebar, jump-to-repo removal,
  Open-in-VSCode).
