---
artifact: ITER_01
status: ready
created: 2026-06-19
scope: Real registry loading (JSON) + recursive plan discovery/read under planning/ + lifecycle status READ from implementation sidecars; both frontends show live read-only data
sections_changed: [03, 04, 05]
sections_unchanged: [01, 02, 06]
depends_on: [SKELETON]
---

# ITER_01 — Real read side (registry + plans + status)

## §01 · Concept

> Unchanged — see SKELETON § 01.

## §02 · Architecture

> Unchanged — see SKELETON § 02. This iteration realizes the **read** half of the data
> model: `Project` (from the JSON registry), `Plan` summaries and bodies (recursive discovery
> under `planning/`), and the lifecycle `status` **read** from the implementation sidecar
> (defaulting to `ready` when no sidecar exists). It realizes the read-only endpoints
> `GET /api/projects` and `GET /api/plan`. **Sidecar writes, manual transitions, and runs
> stay stubbed** (ITER_02/03). docket reads plans but never writes them, now or ever.

## §03 · Tech Stack

- Adds nothing new to install. Uses stdlib `json` (registry **and** sidecars — no
  `tomllib`), `pathlib` (recursive plan discovery), and the in-house `frontmatter` reader
  (title extraction only). `textual` already present from the skeleton.

## §04 · Backend

Implement the read path across `core.py`, `tracker.py`, and the frontmatter reader.

### `frontmatter.py`

```python
def parse(text: str) -> tuple[dict, str]:
    """Split a leading '---' fenced block of flat `key: value` lines from the body.
    Returns (meta_dict, body). No frontmatter -> ({}, text). Values are str. Robust to
    CRLF and to a missing trailing newline. READ-ONLY use this iteration — docket only
    needs `meta.get('title')` for display; it never writes plan files, so there is no
    `dump`."""
```

Lenient: a plan authored by the planning skill may have richer frontmatter; we read what we
can and ignore the rest. **We never read lifecycle status from here** — note the two-status
caveat in SKELETON §02 (a plan's own `status:` is the planning doc's status, not docket's).

### `tracker.py` — sidecar path + read

```python
def sidecar_path(project, slug) -> Path:
    """<project.path>/.agents_workspace/implementation/<slug>.json — mirrors the plan's
    relative path exactly (the parent folder may or may not exist yet; that's fine for a
    read)."""

def read_record(project, slug) -> dict:
    """Load the sidecar JSON. MISSING FILE -> {"slug": slug, "status": "ready",
    "history": []} (not an error — an un-run plan is `ready`). Validate that `status` is one
    of ready|running|implemented; an unrecognised value is treated as `ready` (defensive)."""
```

Writing the sidecar (`set_status`, history append, atomic write) is **ITER_02**; this
iteration only reads.

### `core.py` — read functions

- `load_registry(path=None)` — resolve the registry path (first match wins): explicit
  `path` (from `--registry`) → `$DOCKET_REGISTRY` → `./projects.json` →
  `~/.config/docket/projects.json`. If none exists, return `[]` (frontends render the empty
  state with the search paths) — not an error. Otherwise `json.load` it; expect
  `{"projects": [ {...}, ... ]}` plus an optional top-level `"instruction_template"` (read
  and stashed for ITER_03; ignored here). Each project entry: `name` + `path` (+ optional
  `allowed_tools`, `model`, `max_turns`). Resolve `path` with `expanduser` to an absolute
  path. Raise a clear error naming the offending entry if `path` is set but not a directory,
  if `name` is missing/duplicated, or if the top-level shape isn't
  `{"projects": [...]}`. Return `list[Project]`.
- `list_plans(project)` — **recursively** glob
  `Path(project.path)/".agents_workspace"/"planning"/"**"/"*.md"`. For each file: compute
  `slug` = path **relative to `planning/`** with the `.md` suffix removed (so nested files
  get slugs like `feature-x/ITER_01`, always with forward slashes regardless of OS). Build a
  **summary** `Plan` (`body=""`): `title` from `frontmatter.parse(...).get('title')` else
  the slug; `status` from `tracker.read_record(project, slug)["status"]`. Missing
  `planning/` dir → empty list (not an error). Sort by status then slug (deterministic
  ordering; the frontends render nested slugs as a tree).
- `read_plan(project, slug)` — **validate the slug first** (see below), then read
  `<planning>/<slug>.md`, parse for `title`, attach `status` + `history` from
  `tracker.read_record`. Return a full `Plan` with `body`. Missing file → raise
  `FileNotFoundError` with project+slug in the message.

**Slug validation** (security-relevant — slug becomes a path *and* a URL/query value):
accept one or more `/`-separated segments each matching `^[A-Za-z0-9._-]+$`; **reject** any
segment equal to `..` or `.`, a leading/trailing `/`, an empty slug, and any absolute path.
This permits subfolders while making it impossible to escape `planning/`. A single helper
(`safe_slug(slug) -> str` raising `ValueError`) is used by every function that takes a slug,
here and in later iterations.

`projects.json` sample (committed):

```json
{
  "instruction_template": "Read the plan at {path} and implement it fully. The plan may reference sibling files (e.g. a SKELETON or earlier iterations) — read those as needed. Make the code changes the plan describes.",
  "projects": [
    { "name": "pyxyflow", "path": "~/code/pyxyflow" },
    { "name": "mcp-harness", "path": "~/code/mcp-harness", "model": "claude-sonnet-4-6", "max_turns": 40 }
  ]
}
```

(`instruction_template` is optional; omit it to use `DEFAULT_INSTRUCTION_TEMPLATE`. It is
read in ITER_01 but only *used* in ITER_03.)

### Endpoint shapes (browser)

- `GET /api/projects` → `{"projects":[{"name","path","plans":[{"slug","title","status"}]}]}`
  — built from `load_registry` + `list_plans`. No pagination (local, ~10 repos × few plans;
  deferred).
- `GET /api/plan?project=&slug=` → `{"project","slug","title","status","body","history"}`
  from `read_plan`. The handler **URL-decodes** `slug` (it may contain `%2F`). Unknown
  project/slug → HTTP 404 with `{"error": "..."}`. Invalid slug (validation above) → HTTP
  400. (Single-user local tool, so ownership-leakage 403-vs-404 concerns do not apply.)

Registry read errors surface as HTTP 500 with the clear message from `load_registry`.

## §05 · Frontend

Replace skeleton stubs with real data in **both** frontends (same core/tracker, swapped
once):

- **TUI:** on mount, `load_registry()` → populate the project/plan **tree** (nested slugs
  rendered hierarchically) with real entries and a `ready/running/implemented` status badge
  per plan; selecting a plan calls `read_plan` and renders the body **read-only** (there is
  no edit affordance — docket never edits plans). Empty registry → the "edit projects.json"
  empty state from the skeleton. A read error renders in the log pane rather than crashing.
- **Browser:** `app.js` fetches `/api/projects` on load and renders the tree (URL-encoding
  each `slug` when it later requests a plan); clicking a plan fetches `/api/plan` and shows
  the body read-only. Loading and error states (stubbed in the skeleton) now reflect real
  fetch outcomes. The run controls — Implement, Run-myself, Mark-implemented, Reopen, Stop —
  are rendered **disabled** this iteration with an "available next" note; the manual
  controls + run-myself wire up in ITER_02 and the headless run controls in ITER_03. The
  skeleton's convention holds: render-disabled, don't hide.

## §06 · LLM / Prompts

> Unchanged — see SKELETON § 06. No LLM activity in this iteration.
