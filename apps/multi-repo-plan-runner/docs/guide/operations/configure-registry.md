# Configure the registry

The registry is a single JSON file, `.docket.json`, that tells docket which repos exist and how
to run each one. It is the only file you edit to operate docket.

## Where docket looks for it

Resolution order, **first match wins**:

1. `--registry PATH` (passed to `docket tui`, `docket serve`, or `docket doctor`)
2. `$DOCKET_REGISTRY` environment variable
3. `./.docket.json` (current working directory)
4. `~/.config/docket/.docket.json`

If none exists, docket does **not** error — both frontends show a "no projects" empty state, and
`docket serve` prints the exact paths it searched. To see those paths, start the server with no
registry present.

> Renamed from v1: docket no longer reads `projects.json`. If you have an old one, regenerate with
> `docket init --scan` or point `--registry old.json` at it once. A top-level `instruction_template`
> in an old file is still honoured (it seeds the `defaults` layer).

## Don't author it by hand — generate it

```
docket init                 # write a full default ./.docket.json (every knob at its default)
docket init --scan ~/code   # also pre-populate projects from repos that contain a planning/ dir
docket init --dry-run       # print what would be written, touch nothing
```

`init` refuses to overwrite an existing file unless you pass `--force`. As your set of repos
grows, re-run with `--merge` to add only newly-discovered repos **without touching** your existing
entries, `defaults`, or `port`:

```
docket init --scan ~/code --merge
```

The generated file carries a `$schema` pointer so editors (VS Code, etc.) give you autocomplete,
inline docs, and validation while you edit. docket itself never reads the schema at runtime.

## File shape — three layers

```json
{
  "$schema": "docket/schema/docket.schema.json",
  "port": 8765,
  "defaults": {
    "instruction_template": "Read the plan at {path} and implement it fully. ...",
    "model": "claude-sonnet-4-6",
    "max_turns": 40
  },
  "projects": [
    { "name": "pyxyflow", "path": "~/code/pyxyflow" },
    { "name": "mcp-harness", "path": "~/code/mcp-harness", "max_turns": 30 }
  ]
}
```

This is JSON only — no YAML, no TOML. The three tiers:

- **Top-level** — app settings that aren't per-project: `port` (default for `docket serve`; the
  `--port` flag overrides) and the read-and-ignored `$schema` pointer.
- **`defaults`** — the baseline for every per-project knob. A project that doesn't set a knob
  inherits it from here; a knob unset here too falls back to docket's built-in default.
- **`projects[]`** — one entry per repo. `name` + `path` are required; every `defaults` knob may
  be overridden per project.

Each value resolves lowest → highest: **built-in default → `defaults.<knob>` → `project.<knob>`**.
For `instruction_template` only, a fourth and highest layer applies at submit time: the per-plan
override you type when implementing.

## Per-project knobs

| Knob | Default | Purpose |
|------|---------|---------|
| `name` | — (required) | Unique display name. Duplicate names are rejected. |
| `path` | — (required) | Repo path; `~` and `$VARS` are expanded. **Must be an existing directory.** |
| `allowed_tools` | `Read, Edit, Write, Bash(pytest:*), Bash(npm test:*), Bash(npm run test:*)` | Tools the headless agent may use (`--allowedTools`). A project's list **replaces** the defaults list. |
| `instruction_template` | built-in template | Headless stdin instruction; `{path}` → the plan's repo-relative path. |
| `model` | the CLI's configured model | Pins the model (`--model`). |
| `max_turns` | `30` | Caps the agent loop (`--max-turns`). |
| `permission_mode` | `acceptEdits` | `--permission-mode`; one of `acceptEdits`, `default`, `plan`, `bypassPermissions`. |
| `planning_dir` | `.agents_workspace/planning` | Where docket discovers plans. |
| `implementation_dir` | `.agents_workspace/implementation` | Where docket writes status sidecars. |
| `claude_bin` | `claude` | The Claude Code executable (resolved on PATH or as an explicit file; `~`/`$VARS` expanded). |
| `claude_extra_args` | `[]` | Extra flags appended last to the `claude` invocation (e.g. `--add-dir`). Don't restate the streaming flags. |

## Check it before you run: `docket doctor`

```
docket doctor                 # uses the normal resolution order
docket doctor --registry PATH
```

`doctor` loads the registry and reports problems: a missing `planning_dir`, an unknown
`permission_mode`, an empty `allowed_tools`, or a `claude_bin` not resolvable on PATH. It exits
`0` when clean (warnings allowed) and `1` on any error-level finding, so it works as a pre-run or
CI gate.

## Procedure: add a repo

1. Open your `.docket.json` (or run `docket init --scan ~/code --merge` to discover it).
2. Add an entry to `projects` with a unique `name` and a valid `path`:

   ```json
   { "name": "my-repo", "path": "~/code/my-repo" }
   ```

3. Save the file, then run `docket doctor` to confirm it's healthy.

**Verify:** restart the frontend (or just refresh the browser page — docket reloads the registry
on every request) and confirm the project appears with its plans. If you see no plans under it,
the repo has no files under `<path>/<planning_dir>`.

**If it fails:** docket raises a clear, named error and the browser shows it as an HTTP 500:

- `project '<name>' path is not a directory` — fix the `path`.
- `duplicate project name '<name>'` — names must be unique.
- `a project entry is missing 'name'` / `missing 'path'` — add the required field.
- `expected top-level shape {"projects": [...]}` — the file isn't a JSON object with a `projects`
  list.

## Notes for operators

- docket reads the registry on **every** request/startup, so edits take effect without a restart
  on the browser side. The TUI reads it once at launch.
- A plan's own `status:` frontmatter is ignored. Lifecycle status comes only from the sidecar — do
  not try to drive status through the plan file.
