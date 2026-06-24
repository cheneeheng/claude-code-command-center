# Getting started

Goal: from a fresh checkout to one plan implemented through docket, in about five minutes.

## Before you begin

You need:

- **Python 3.11 or newer.** Check with `python --version`.
- **The `claude` CLI installed and authenticated.** docket shells out to it for headless runs and
  never handles API keys. Confirm with `claude --version`. (You can skip this if you only intend
  to use *manual* mode, where you run Claude Code yourself.)
- **At least one repo with a plan** under `<repo>/.agents_workspace/planning/<name>.md`. Plans are
  authored with the planning skill; docket only reads them.
- **`uv`** (recommended) or `pip`. This guide shows `uv`; the `pip` fallback is in
  [Install docket](operations/install.md).

## 1. Install docket

From the docket source directory:

```bash
uv sync
```

**Verify:** the install finished without errors and the CLI responds:

```bash
uv run docket --help
```

You should see a usage line listing the `tui`, `serve`, `init`, and `doctor` subcommands.

## 2. Tell docket about your repo

docket finds your repos through a `.docket.json` registry. Generate one instead of writing it by
hand — `init` writes a complete file with every knob at its default:

```bash
uv run docket init                 # write ./.docket.json
uv run docket init --scan ~/code   # also discover repos that have a planning/ dir under ~/code
```

Then open `.docket.json` and make sure `projects` lists your repo:

```json
{
  "projects": [
    { "name": "my-repo", "path": "~/code/my-repo" }
  ]
}
```

Replace `path` with the absolute path (or `~`-path) to a repo that has a plan under
`.agents_workspace/planning/`. Run `uv run docket doctor` to sanity-check the result.

**Verify:** the path points at a real directory. docket refuses to start a project whose `path`
is not a directory. Full field list and resolution order: [Configure the
registry](operations/configure-registry.md).

## 3. Open docket

Pick one frontend — they do the same thing over the same core.

Terminal UI:

```bash
uv run docket tui
```

Browser page:

```bash
uv run docket serve
```

…then open <http://127.0.0.1:8765>.

**Verify:** you see your project name with its plans listed underneath, each with a status badge.
Every plan with no prior run shows **ready**. If you instead see "no projects — edit
.docket.json", docket didn't find your registry — see [Configure the
registry](operations/configure-registry.md).

## 4. Implement your first plan

The fastest path is *manual* mode — it needs no headless setup and changes no status until you say
so.

1. Select a plan. In the TUI, arrow to it and press **Enter**; in the browser, click its row. The
   plan body renders read-only on the right.
2. Trigger **Run myself** (TUI: press **r**; browser: click **Run myself**). docket copies the
   plan body to your clipboard and prints a ready-to-paste command to the log.
3. Paste that command into your own terminal and run Claude Code as usual.
4. When the work is done, trigger **Mark implemented** (TUI: press **m**; browser: click **Mark
   implemented**).

**Verify:** the plan's badge flips from **ready** to **implemented**, and a transition is now
recorded in its sidecar at `<repo>/.agents_workspace/implementation/<slug>.json`.

## You're set up

From here:

- Let docket run Claude Code for you and stream the output: [Implement a plan
  headless](how-to/implement-headless.md).
- Run several plans in one submission: [Implement a batch of plans](how-to/batch-implement.md).
- Run a finished plan again, or send it back to `ready`: [Re-run or reopen a
  plan](how-to/re-run-and-reopen.md).
