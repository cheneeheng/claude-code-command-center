---
artifact: ITER_02
status: ready
created: 2026-06-19
scope: The implementation sidecar tracker (status + history writes) and the complete MANUAL mode — mark implemented, reopen, and a copy-pasteable run-it-yourself command. No subprocess.
sections_changed: [04, 05]
sections_unchanged: [01, 02, 03, 06]
depends_on: [SKELETON, ITER_01]
---

# ITER_02 — Tracker writes + manual mode

## §01 · Concept

> Unchanged — see SKELETON § 01.

## §02 · Architecture

> Unchanged — see SKELETON § 02. This iteration realizes the **write** side of the
> implementation sidecar (status + history), the **manual** lifecycle transitions
> `ready → implemented` and `implemented → ready`, and the run-it-yourself command. It
> introduces **no subprocess, no Run, no lock, no `running` state** — manual mode is pure
> status management plus one string. The `running` transitions and `reset_stale_runs()`
> belong to the headless runner in ITER_03 (nothing can reach `running` until then).
> Endpoints added: `POST /api/implemented`, `POST /api/reopen`, `GET /api/runcmd`.

## §03 · Tech Stack

> Unchanged — see SKELETON § 03. No new dependencies (stdlib `json`, `os`, `datetime` for
> the atomic sidecar write and timestamps; the `safe_slug` helper from ITER_01).

## §04 · Backend

Add the sidecar **write** path to `tracker.py` and the manual-command builder to `core.py`.

### `tracker.py` — transitions + history (writes)

```python
ALLOWED = {  # (from, to): {triggers}  — the full lifecycle table from SKELETON §02
    ("ready", "running"): {"headless"},
    ("implemented", "running"): {"headless"},
    ("running", "implemented"): {"headless"},
    ("running", "ready"): {"headless", "startup_reset"},
    ("ready", "implemented"): {"manual"},
    ("implemented", "ready"): {"manual"},
}

def set_status(project, slug, to, *, trigger, run_id=None, rc=None) -> dict:
    """Read the current record (read_record from ITER_01; missing -> ready/[]), validate
    (current_status, to) is in ALLOWED and `trigger` is permitted for that edge, append a
    history record, and atomically write the sidecar. Returns the updated record.
    Raises ValueError on an illegal transition or disallowed trigger, naming both states."""
```

- **History record** appended on every successful transition:
  `{"ts": <ISO-8601 UTC, e.g. 2026-06-19T13:45:02Z>, "from": <prev|null>, "to": <to>,
  "trigger": <"headless"|"manual"|"startup_reset">, "run_id": <run_id|null>,
  "rc": <rc|null>}`. The first transition records `"from"` as the current status (usually
  `ready`). **Manual transitions are logged with `trigger:"manual"`, `run_id:null`,
  `rc:null`** — this is point (7): a hand-driven completion or reopen is recorded in the
  same per-plan history as a headless one, distinguished only by the trigger.
- **Atomic write:** ensure
  `<project.path>/.agents_workspace/implementation/<slug parent dirs>/` exists
  (`mkdir(parents=True, exist_ok=True)` — the mirrored subfolder may not exist yet). Write to
  a temp file **in the same directory** as the target sidecar (so the rename stays on one
  filesystem), `json.dump`, then `os.replace` over the target. A crash can never leave a
  half-written sidecar.
- This iteration only ever calls `set_status` with the **manual** edges
  (`ready→implemented`, `implemented→ready`). The `running`/`startup_reset` edges are in the
  table now so the lifecycle is defined in one place, but the code that drives them arrives
  in ITER_03.

### `core.py` — the run-it-yourself command

```python
def manual_command(project, slug) -> str:
    """Pure string building (no precondition beyond the plan existing — validate slug).
    Return a copy-pasteable command for running the plan yourself, e.g.:

        cd <project.path> && claude -p < .agents_workspace/planning/<slug>.md

    with an interactive variant in a trailing comment:

        # or: cd <project.path> && claude   (then paste / @-mention the plan file)
    """
```

Note this hands you the **plan file** to run by hand (the `<` redirect feeds the plan body
to your own `claude -p`); docket's *headless* path differs deliberately — it pipes a short
*instruction naming the file*, not the body (SKELETON §06, realized in ITER_03). Manual mode
is your session, so you drive it however you like; docket only tracks the outcome.

### Endpoint shapes (browser)

- `POST /api/implemented` — body `{project, slug}` → `{ok:true, status:"implemented"}` via
  `set_status(..., "implemented", trigger="manual")`. Allowed only from `ready`; from
  `running` or `implemented` → HTTP 409 with the returned message
  (e.g. "is running — stop it first" / "already implemented").
- `POST /api/reopen` — body `{project, slug}` → `{ok:true, status:"ready"}` via
  `set_status(..., "ready", trigger="manual")`. Allowed only from `implemented`; otherwise
  HTTP 409.
- `GET /api/runcmd?project=&slug=` → `{"cmd": "..."}` from `manual_command`. URL-decode
  `slug`; unknown project/slug → 404; invalid slug → 400.

POST handlers read the JSON body from the stdlib handler (`Content-Length` read +
`json.loads`); malformed JSON → 400.

## §05 · Frontend

Enable the **manual** controls (rendered-disabled in ITER_01) in **both** frontends. The
headless `[Implement]`/`[Stop]` controls stay disabled with their "available next" note
(ITER_03).

- **TUI:**
  - `[Run myself]` binding — calls `manual_command`, **copies the plan body to the
    clipboard**, and prints the command to the log pane. Status is **unchanged** (`ready`
    stays `ready`) — docket isn't running anything; you are.
  - `[Mark implemented]` binding — `set_status(..., "implemented", trigger="manual")`; badge
    flips `ready → implemented`. Enabled only when status is `ready`.
  - `[Reopen]` binding — `set_status(..., "ready", trigger="manual")`; badge flips
    `implemented → ready`. Enabled only when status is `implemented`.
  - A transition that's rejected (e.g. trying to mark a `running` plan) surfaces as a brief
    notice, not a crash.
  - Plan view remains **read-only** throughout (no plan editing in docket, ever).
- **Browser:**
  - `Run myself` button (enabled when `ready` or `implemented`) → `GET /api/runcmd`, show
    the returned `cmd`, and copy the plan body via `navigator.clipboard.writeText` (needs
    the `localhost`/secure-context clipboard API; fall back to selecting the command text if
    unavailable). Status unchanged.
  - `Mark implemented` button (shown/enabled only when `ready`) → `POST /api/implemented`,
    then re-fetch the plan + project list so the badge updates. On 409, show the returned
    message inline.
  - `Reopen` button (shown only when `implemented`) → `POST /api/reopen`, then re-fetch.
  - `Implement`/`Stop` stay **disabled** with the "available next" note (ITER_03).

## §06 · LLM / Prompts

> Unchanged — see SKELETON § 06. No LLM activity in this iteration — manual mode runs in
> *your* terminal; docket only records the status transition.
