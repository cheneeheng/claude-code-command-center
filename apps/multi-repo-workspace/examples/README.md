# Runnable example

A zero-setup board so you can see roundtable working before pointing it at your own repos. It ships two stand-in repos under `sample-repos/`, each with plans already in `.agents_workspace/planning/`, plus a registry (`roundtable.json`) that points at them.

```
examples/
├── roundtable.json             # registry for the two sample repos (relative paths)
└── sample-repos/
    ├── web-app/                # 2 plans (one nested under feature-search/)
    └── api-service/            # 1 plan
```

## Run it

> The registry uses **relative** paths, so run every command from the member root (`apps/multi-repo-workspace/`) — the directory that contains `examples/`. roundtable resolves project paths against your current directory.

```bash
uv run roundtable --registry examples/roundtable.json serve
```

…then open <http://127.0.0.1:8640>.

**Verify:** the board shows two cards — **web-app** (with `add-dark-mode-toggle` and `feature-search/ITER_01`) and **api-service** (with `add-health-endpoint`). The sample repos are deliberately **not** git repositories, so each card shows a git warning strip — that is expected, and it exercises the board's degraded-repo rendering. Everything plan-related still works: open a repo, browse the Plans and Files tabs, read a plan with full markdown rendering.

First, you can sanity-check the registry resolves cleanly:

```bash
uv run roundtable --registry examples/roundtable.json doctor
```

**Verify:** it reports both projects with no errors. A warning about `claude` not being on PATH is fine for browsing — you only need the `claude` CLI for planning sessions and End Turn.

## Walk the lifecycle (no `claude` CLI needed)

Plan lifecycle state lives in status sidecars, not in the plan files, so you can watch a badge move without running anything:

1. Open **web-app** from the board and pick `add-dark-mode-toggle` in the **Plans** tab. Its body renders read-only.
2. Use **Mark implemented** in the plan view.

**Verify:** the plan's badge flips **ready → implemented**, and the board's plan counts update on the next poll.

Planning sessions, orders, and End Turn shell out to the real `claude` CLI — for those, point roundtable at your own repos (see the member [README](../README.md#quick-start)).

## Reset the example

Marking a plan implemented writes a status sidecar under the sample repo's `.agents_workspace/implementation/`. Those are git-ignored, so the example always starts fresh on a clean checkout. To reset an existing checkout, delete the sidecar trees:

```bash
rm -rf sample-repos/*/.agents_workspace/implementation
```

**Verify:** every plan shows **ready** again (a plan with no sidecar is `ready`).
