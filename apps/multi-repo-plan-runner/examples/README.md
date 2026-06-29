# Runnable example

A zero-setup workspace so you can see docket working before pointing it at your
own repos. It ships two stand-in repos under `sample-repos/`, each with plans
already in `.agents_workspace/planning/`, plus a registry (`docket.json`) that
points at them.

```
examples/
├── docket.json                 # registry for the two sample repos (relative paths)
└── sample-repos/
    ├── web-app/                # 2 plans (one nested under feature-search/)
    └── api-service/            # 1 plan
```

## Run it

> The registry uses **relative** paths, so run every command from the
> member root (`apps/multi-repo-plan-runner/`) — the directory that contains
> `examples/`. docket resolves project paths against your current directory.

Terminal UI:

```bash
uv run docket --registry examples/docket.json tui
```

Browser page:

```bash
uv run docket --registry examples/docket.json serve
```

…then open <http://127.0.0.1:8765>.

**Verify:** you see two projects — **web-app** (with `add-dark-mode-toggle` and
`feature-search/ITER_01`) and **api-service** (with `add-health-endpoint`) —
each plan showing a **ready** badge.

First, sanity-check the registry resolves cleanly:

```bash
uv run docket --registry examples/docket.json doctor
```

**Verify:** it prints `2 project(s): 0 error(s), …`. A warning about `claude`
not being on PATH is fine — you only need the `claude` CLI for *headless* runs,
not for the manual walkthrough below.

## Implement a plan (manual mode — no `claude` CLI needed)

Manual mode changes no files and needs no API key; it just exercises the
lifecycle so you can watch a badge move.

1. Select a plan (TUI: arrow to it, **Enter**; browser: click its row). Its body
   renders read-only.
2. Trigger **Run myself** (TUI: **r**; browser: **Run myself**). docket copies a
   copy-pasteable command to the log — you don't have to run it for this demo.
3. Trigger **Mark implemented** (TUI: **m**; browser: **Mark implemented**).

**Verify:** the plan's badge flips **ready → implemented**.

## Reset the example

Marking a plan implemented writes a status sidecar under each sample repo's
`.agents_workspace/implementation/`. Those are git-ignored, so the example
always starts fresh on a clean checkout. To reset an existing checkout, delete
the sidecar trees:

```bash
rm -rf sample-repos/*/.agents_workspace/implementation
```

**Verify:** every plan shows **ready** again (a plan with no sidecar is `ready`).

## Next

This mirrors the full [Getting started](../docs/guide/getting-started.md) flow
with the bring-your-own-repo step already done. When you're ready for real
repos, see [Configure the registry](../docs/guide/operations/configure-registry.md).
