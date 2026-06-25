---
artifact: skeleton
title: Claude Code Command Center — Monorepo Skeleton
status: proposed
created: 2026-06-25
scope: Consolidate the five existing reference projects into one categorized monorepo
       and establish the structure, tooling, and growth path for "the ultimate repo
       centered around Claude Code."
---

# Claude Code Command Center — Build Plan

## 1. Vision

A single monorepo that is the **command center for working with Claude Code**: utility
tools, developer tools, full apps, and shared libraries — all centered on Claude Code.
The repo is already named `claude-code-command-center`; "docket" already describes itself
as "a command-center over the ~10 Claude Code repos you work across," so the theme is
consistent.

The five projects currently under `reference/` are **not throwaway examples — they are the
initial substance of the repo** (decision confirmed with the user). They get promoted to
first-class, categorized top-level members. New tools/apps/libraries are added alongside
them over time.

## 2. Inventory of what we already have

| Project | Category | Stack | Maturity signals | Notes |
|---|---|---|---|---|
| `vantage` | App | Static HTML/CSS/JS (serverless, File System Access API) | README, CHANGELOG, CLAUDE.md, docs/ | No build, no deps. Chromium-only. |
| `docket` | App | Python + `uv` (pyproject, uv.lock) | README, CHANGELOG, CLAUDE.md, tests/, .github/, agents_workspace/ | Most "real" Python project. TUI/command-center over plans. |
| `claude-code-plugin-toggler` | App / Dev tool | Python stdlib server + Node.js VSCode extension | README, CHANGELOG, CLAUDE.md, Makefile, tests/, .github/ | Two surfaces (web UI + VSCode). No npm runtime deps. |
| `claude-automation` | Utility tool | PowerShell + Bash + Python stdlib | README, docs/ | statusline hook, dashboard server, settings/CLAUDE.md sync. Windows-leaning. |
| `claude-code-scheduler` | Utility tool | PowerShell + Bash + cron + CC skills | README, CHANGELOG, VERSION, docs/, skills/ | Unattended scheduled automations. Bundles `skills/`. |

Language footprint today: ~31 Python, ~26 JS, ~24 PowerShell, ~17 Bash, 5 HTML files.

Common thread (**corrected during Phase 4**): only the **dashboard** actually parses
`~/.claude/projects/**/*.jsonl` transcripts. docket reads plan files + its own JSON registry
(its "projects" are repos, not `~/.claude/projects`), and the scheduler is shell-based. So the
shared parsing had one consumer until a second was built — see Phase 4.

## 3. Target top-level structure

Grouped by category, matching the user's own framing. Drop the redundant `claude-code-`
prefix on members since the whole repo is about Claude Code.

```
claude-code-command-center/
├── README.md                # vision + catalog table + quick links (the front door)
├── LICENSE                  # single repo license (consolidated)
├── CONTRIBUTING.md          # how to add a new member; per-category conventions
├── CHANGELOG.md             # repo-level changelog (members keep their own too)
├── .gitignore
├── apps/                    # full applications a user runs
│   ├── vantage/
│   ├── docket/
│   └── plugin-toggler/      # was claude-code-plugin-toggler
├── tools/                   # utility / developer tooling & scripts
│   ├── automation/          # was claude-automation
│   └── scheduler/           # was claude-code-scheduler
├── libs/                    # shared libraries (Phase 4)
│   └── claude-usage/        # ~/.claude transcript parsing + pricing (built in Phase 4)
├── plugins/                 # packaged Claude Code skills/plugins (Phase 6, optional)
├── docs/                    # monorepo-wide docs: architecture, catalog, decisions
└── .github/workflows/       # aggregate, path-filtered CI
```

Decisions baked in (challenge any of these):
- **Category dirs, not flat.** `apps/ tools/ libs/ plugins/` mirror the user's wording and
  keep the root legible as the set grows.
- **Members keep their own README/CHANGELOG/CLAUDE.md/tests.** The monorepo adds an
  umbrella layer; it does not flatten or rewrite each project.
- **Relocate with `git mv`** so history is preserved.
- **No per-project source changes in the relocation phase.** Internal-path fixes (if any
  break) are handled as their own follow-up, not smuggled into the move.

## 4. Phased plan

Each phase is independently shippable. Phase 0 is this document.

### Phase 0 — Plan (this session) ✅
Deliverable: this `SKELETON.md` + a Decision Log entry. No code moved.

### Phase 1 — Skeleton & relocation
- Create `apps/ tools/ libs/ plugins/ docs/`.
- `git mv` the five projects to their category homes with the renamed paths above.
- Add root `LICENSE` (consolidate `reference/LICENSE`; confirm it's the intended one),
  `.gitignore`, and a minimal placeholder root `README.md`.
- Remove the now-empty `reference/` dir.
- Success check: `git status` shows renames (not delete+add); every member still has its
  own README at its new path; nothing inside members changed.

### Phase 2 — Root catalog & docs (the "front door")
- Flesh out root `README.md`: vision, the catalog table from §2 (with links), quick-start
  per member, and a "how to add a member" pointer.
- `CONTRIBUTING.md`: category conventions (Python→uv/ruff/mypy; web→Bun/Vite where it
  applies; scripts→PowerShell+Bash parity), member layout checklist.
- `docs/architecture.md`: the structure rationale + the shared-parsing observation.
- Repo-level `CHANGELOG.md` seeded.

### Phase 3 — Unified CI
- One path-filtered GitHub Actions workflow that runs each member's existing checks only
  when that member's files change (matrix by member).
- Fold in the existing `.github` from `docket` and `plugin-toggler` rather than duplicating.
- Python members: `uv` + `ruff` + `mypy` + `pytest`. JS surface (VSCode ext): its existing
  Node test path. Static/script members: lint where meaningful (shellcheck, PSScriptAnalyzer).
- (Delegate authoring to the `ceh-ops:github-actions` agent.)

### Phase 4 — Shared library (`libs/`) ✅ (premise corrected)
The original premise — docket + scheduler + dashboard all parse transcripts — was **wrong**;
only the dashboard did. A single-consumer extraction would be a forced abstraction, so a real
second consumer was built first: the `usage-report` CLI. With two genuine consumers, the shared
parsing was extracted into `libs/claude-usage` (src/ layout, `dependencies = []`, strict mypy,
public API in `__init__.py`), and the dashboard was refactored onto it (output verified byte-for-
byte identical). Rule recorded in CLAUDE.md: a lib needs a **cohesive domain AND ≥2 consumers** —
extract on the second consumer, not the first.

### Phase 5 — First new flagship piece
- Pick and build one net-new member to demonstrate the repo is alive and additive.
  Candidates to choose from later: a CLI that aggregates token/cost across all sessions
  (builds on Phase 4 lib), a skills/plugin browser, or a unified `cc` launcher over the
  apps. **Decide with the user when we get here.**

### Phase 6 — Plugin/skill marketplace (optional)
- If desired, expose `scheduler/skills/` (and any future skills) as installable Claude Code
  plugins via a `marketplace.json` under `plugins/`. Optional and deferred.

## 5. Open decisions to confirm before Phase 1

1. **Member renames** — OK to drop the `claude-code-` prefix (`plugin-toggler`, `scheduler`)
   and shorten `claude-automation`→`automation`? Or keep original names?
2. **License** — `reference/LICENSE` is the only license present (no root LICENSE yet). Use
   it as the single repo license? Which license is it (need to confirm — likely the same for
   all members)?
3. **Python workspace** — adopt a `uv` workspace tying docket + future libs together, or keep
   each Python project independent for now? (Recommend: independent in Phase 1, workspace in
   Phase 4 when `libs/` appears.)
4. **CLAUDE.md** — add a root `CLAUDE.md` describing the monorepo to Claude Code, while
   keeping each member's own? (Recommend: yes, in Phase 2.)

## 6. Out of scope (explicitly, for now)
- Rewriting or "harmonizing" the internals of existing members.
- Cross-language build orchestration (Nx/Turborepo/Bazel) — not justified at this size.
- Publishing anything to PyPI / VSCode Marketplace / a CC marketplace this session.
- Performance work, new dependencies inside existing members.

---

**Recommended next step:** confirm the four open decisions in §5, then I execute Phase 1
(skeleton + `git mv` relocation) as a single reviewable commit.
