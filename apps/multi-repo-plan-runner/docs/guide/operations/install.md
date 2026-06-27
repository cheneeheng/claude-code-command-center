# Install docket

Stand docket up on a machine and confirm it's healthy.

## Requirements

| Requirement | Why | Check |
|-------------|-----|-------|
| Python 3.11+ | Runtime. | `python --version` |
| `uv` (recommended) or `pip` | Install + run. | `uv --version` |
| `textual` | The TUI. Installed automatically; it is the only pip dependency. | — |
| `claude` CLI, authenticated | Headless runs shell out to it. **Not** needed for manual mode. docket never handles API keys. | `claude --version` |

The browser frontend is pure stdlib — no extra dependencies, no build step.

## Install (uv, recommended)

`uv` reads the committed `uv.lock` for a reproducible environment.

```bash
uv sync
```

**Verify:**

```bash
uv run docket --help
```

Expected: a usage line listing the `tui` and `serve` subcommands. Then run the test suite to
confirm the install is sound:

```bash
uv run pytest
```

Expected: all tests pass at 100% coverage.

## Install (pip fallback)

Use this only if `uv` is unavailable.

```bash
pip install -e .
```

**Verify:**

```bash
docket --help
```

## Post-install health check

1. Create a minimal registry in the current directory:

   ```json
   { "projects": [] }
   ```

2. Start the browser server:

   ```bash
   uv run docket serve
   ```

   **Verify:** the console prints `serving on http://127.0.0.1:8765`. Because the registry is
   empty, it also prints `no projects — searched:` followed by the registry search paths. Open
   <http://127.0.0.1:8765> and confirm the page loads with a "no projects — edit .docket.json"
   message. Press **Ctrl-C** to stop; the console prints `shutting down`.

Next: [Configure the registry](configure-registry.md) to point docket at real repos.

## Common failures

- **`docket: command not found` (pip install).** The console script isn't on `PATH`. Use
  `python -m docket …`, or prefer the `uv run docket …` form.
- **`claude: command not found` during a headless run.** The CLI isn't installed or not on
  `PATH`. Install and authenticate it, or use manual mode, which doesn't need it.
- **Wrong Python picked up.** Ensure `python --version` is 3.11+. With `uv`, the project pins its
  interpreter; prefer `uv run …` over a system `python`.
