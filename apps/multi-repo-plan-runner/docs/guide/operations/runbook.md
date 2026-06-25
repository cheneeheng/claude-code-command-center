# Operations runbook

Routine operation and incident recovery for docket. Terse and copy-pasteable.

## System overview

- **Two frontends, one core.** `docket tui` (Textual) and `docket serve` (stdlib
  `ThreadingHTTPServer`) both import the same `core` + `tracker`. No web framework, no database.
- **State on disk.** The only persistent state docket owns is the sidecar tree:
  `<repo>/.agents_workspace/implementation/<slug>.json`, one file per plan, holding status +
  transition history. Plans under `planning/` are read-only to docket.
- **Runs are in-memory only.** A headless run's process, queue, and batch grouping live in the
  process; nothing about a live run is persisted. The sidecar records the status *transitions*,
  not the run output.
- **Network.** `docket serve` binds `127.0.0.1` only — not reachable off-box. That is the entire
  auth story for this single-user tool. There is no login.

## Routine operations

### Start the browser server

```bash
uv run docket serve --port 8765
```

Default port is `8765`. **Verify:** console prints `serving on http://127.0.0.1:8765`.

### Stop the server

Press **Ctrl-C** in its terminal. **Verify:** console prints `shutting down`. On startup *and*
this clean shutdown, in-flight headless runs are child processes of docket — stopping the server
does not wait for them; treat any plan left `running` as stale (see below).

### Start the TUI

```bash
uv run docket tui
```

### Point either frontend at a specific registry

```bash
uv run docket serve --registry /path/to/.docket.json
uv run docket tui   --registry /path/to/.docket.json
```

See [Configure the registry](configure-registry.md) for resolution order.

## Monitoring

There are no metrics or dashboards — this is a local tool. What to watch:

- **Plan badges** in either frontend are the live health view: `ready` / `running` /
  `implemented`.
- **The run log pane** streams a headless run's output in real time. It is not persisted; once the
  stream ends, only the status transition remains in the sidecar.
- **Sidecar history** is the audit trail. To inspect a plan's transitions:

  ```bash
  cat <repo>/.agents_workspace/implementation/<slug>.json
  ```

  Each history record has `ts`, `from`, `to`, `trigger` (`headless` | `manual` | `startup_reset`),
  `run_id`, and `rc`.

## Incident: a plan is stuck in `running`

**Detection:** a plan shows `running` but no run is actually in flight (e.g. docket crashed or was
killed mid-run, or the machine rebooted).

**Why it happens:** runs are in-memory only, so a sidecar persisted as `running` is necessarily
orphaned from a dead process.

**Remediation:** docket self-heals on startup. Both frontends call startup recovery, which walks
every sidecar and flips each `running` back to `ready` (logged with `trigger: "startup_reset"`).

1. Stop any running docket frontend.
2. Start it again:

   ```bash
   uv run docket serve
   ```

   **Verify:** if anything was reset, the console prints `reset N stale run(s) to ready` (the TUI
   writes the same notice to its log pane). The previously stuck plan now shows `ready`.

**If it persists:** confirm no real `claude` process is still editing that repo
(`ps`/Task Manager). If a genuine run is still alive, let it finish or kill it before relying on
the reset.

## Incident: "a run is already active for this project"

**Detection:** starting a headless run is refused with this message.

**Why:** docket holds a per-project lock so two headless runs on the **same repo** can't collide.
This serializes same-repo runs (and is what makes a batch sequential within a project).

**Remediation:**

- If a run is legitimately in flight, wait for it, or **Stop** it (TUI: **s**; browser: **Stop**).
- The lock is **intra-process only.** Running the TUI **and** the server against the *same repo at
  the same time* is **not** cross-process-locked — an accepted MVP limitation. Operate one
  frontend per repo at a time to avoid colliding working-tree edits.

## Incident: port already in use

**Detection:** `docket serve` fails to bind (address already in use).

**Remediation:** pick another port:

```bash
uv run docket serve --port 8766
```

…and open the matching `http://127.0.0.1:8766`.

## Incident: empty / wrong registry

**Detection:** the UI shows "no projects", or the wrong repos appear.

**Remediation:**

1. Start the server with no `--registry` to see the search paths it prints, or pass an explicit
   one:

   ```bash
   uv run docket serve --registry ./.docket.json
   ```

2. Confirm the file resolved is the one you edited (first match wins across `--registry` →
   `$DOCKET_REGISTRY` → `./.docket.json` → `~/.config/docket/.docket.json`).

See [Configure the registry](configure-registry.md) for field-level errors.

## Recovery: rebuild lost status

There is no backup mechanism — the sidecar tree *is* the state. If `implementation/` is deleted,
every plan reverts to `ready` with empty history (a missing sidecar means `ready`). No plan is
ever lost; only status/history is. Re-mark or re-run plans to rebuild status. Back up the
`implementation/` trees with your normal repo backups if history matters to you.

## Escalation

This is a local single-user tool with no service to page. When the runbook runs out:

- Reproduce with `uv run pytest` to confirm the install is intact.
- Inspect the offending sidecar JSON directly (it's human-readable).
- Check `claude --help` for the installed CLI version — headless flags
  (`--output-format stream-json`, `--permission-mode`, `--allowedTools`) can drift across Claude
  Code versions; see [Reference](../reference.md#headless-invocation).
