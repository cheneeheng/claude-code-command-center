# usage-report — Architecture

A thin CLI that prints a cross-session summary of Claude Code token usage and estimated cost — the
terminal counterpart to the `usage-dashboard` app. All parsing and pricing live in the shared
`claude-usage` library; this member is presentation only.

## System context

A one-shot command: read sessions via the library, render three ranked tables to stdout.

```mermaid
flowchart LR
    you([You]) -->|uv run usage-report --top N| cli((usage-report))
    lib["claude-usage<br/>(editable path dependency)"] -->|load_sessions · estimated_cost| cli
    env["$C4_CLAUDE_DIR"] -. via claude-usage .-> lib
    cli -->|formatted tables| term["stdout / terminal"]
```

## Components

One module: `cli.py`. Aggregation helpers rank sessions/projects/models; the pricing and parsing
are imported, never reimplemented.

```mermaid
flowchart TD
    main["main()<br/>argparse --top · load_sessions · totals"]
    tp["_top_projects<br/>aggregate (tokens, cost) by project"]
    bm["_by_model<br/>aggregate per model via estimated_cost"]
    pt["_print_table / _fmt_tokens<br/>label | tokens | $cost rendering"]
    lib["claude-usage<br/>load_sessions · estimated_cost · Session"]

    main --> lib
    main --> tp
    main --> bm
    bm --> lib
    main --> pt
    tp --> pt
    bm --> pt
```

## Key flow — render the report

```mermaid
sequenceDiagram
    participant U as You
    participant M as main
    participant L as claude-usage
    U->>M: usage-report --top N
    M->>L: load_sessions()
    L-->>M: list[Session] (newest first) or []
    alt no sessions
        M-->>U: "No Claude Code sessions found"
    else
        M->>M: totals (tokens, cost)
        M->>M: top N sessions by cost
        M->>M: _top_projects(N) · _by_model()
        M-->>U: three ranked tables
    end
```

## Key Decisions

### 2026-07-02 — Thin presenter over `claude-usage`; a real installable package

**Status:** Accepted
**Context:** The terminal summary needs the same transcript parsing and pricing as the
`usage-dashboard` app. Duplicating that logic would create two sources of truth for cost.
**Decision:** Keep this member presentation-only — `cli.py` calls `claude_usage.load_sessions` and
`estimated_cost` and does nothing but aggregate and format. Unlike the stdlib-only `tools/` scripts,
this is a packaged tool with a `usage-report` console entry point and a single runtime dependency:
`claude-usage`, wired as an editable path source (so `uv sync` is required before first run).
**Consequences:** Parsing/pricing changes land once, in the library, and both consumers pick them
up. The tradeoff versus the zero-setup scripts is a real `uv sync` step. Output keeps cost labelled
"estimated" to stay honest that it is token counts × list price, not billed.
