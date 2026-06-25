# Decision Log

### Entry 1

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Implement docket from the SKELETON → ITER_01..03 plan to MVP.

**Context:** ITER_03 §04 specifies an atomic sidecar write via `os.replace` over the target.
On Windows a just-written target file is transiently locked by Defender/indexer, so an
immediate overwrite deterministically failed with `PermissionError (WinError 5)` in a
round-trip test (mark → reopen on the same plan). Plain `os.replace` to overwrite otherwise
works.
**Decision:** Kept the spec's atomic `os.replace` and added a bounded retry (10× @ 50ms) on
`PermissionError` in `tracker._atomic_write`. This preserves the crash-safety guarantee while
tolerating the platform's transient lock. Not a new dependency; ~6 lines.
**Impact / Risk:** Worst case a status write blocks up to ~0.5s before raising. Negligible for
a local single-user tool. No effect on POSIX where the lock doesn't occur.
**Outcome:** Round-trip test (mark/reopen/headless lifecycle/reset_stale_runs) passes.

### Entry 2

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Batch-implement instruction UX in both frontends (ITER_03 §05).

**Context:** The plan describes a per-plan, individually-editable instruction *panel* for batch
submit (browser) and an instruction prompt (TUI). A full inline multi-textarea panel is
significant UI code not core to the MVP behavior (per-plan distinct instructions).
**Decision:** Satisfied the functional requirement — distinct instruction per plan — with the
minimum UI: the browser collects each selected plan's instruction via sequential
`window.prompt` calls (each pre-filled with the resolved template), and the TUI uses a single
`InstructionModal` for single-implement plus per-plan default resolution for batch. Different
instructions per plan are still possible; the dedicated multi-row panel is deferred.
**Impact / Risk:** Less polished batch UX than the plan's panel; behavior (per-plan
instructions, per-project sequential, concurrent across projects, stop-on-failure) is fully
intact. Easy to upgrade to a panel later without touching core.
**Outcome:** Functional; not yet runtime-tested for a live headless run (requires the `claude`
CLI + `textual` installed).

### Entry 3

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Plan-compliance review (review-against-plan) of the ITER_03 MVP.

**Context:** SKELETON §02 lists `started_at` as a field of the in-memory `Run` record, but the
implemented `core.Run` dataclass omits it and no code path reads or sets a run start time.
**Decision:** Left `started_at` out rather than adding an unused field. It has no consumer in
the MVP (no elapsed-time display, no scheduling), so adding it would be dead code against the
write-less-code / YAGNI defaults. Recorded as a conscious spec deviation instead.
**Impact / Risk:** None functionally. If a future iteration surfaces run duration, add the
field then with its consumer.
**Outcome:** Documented; no code change.

### Entry 4

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Add a pytest suite at 100% coverage (user-requested).

**Context:** `tracker._atomic_write` retried `os.replace` with `for attempt in range(10): ... if
attempt == 9: raise`. The loop can never complete normally (it always returns on success or
raises on the 10th failure), leaving an unreachable branch that blocks 100% branch coverage.
**Decision:** Rewrote the retry as `for _ in range(9): try/except+sleep` followed by a final
bare `os.replace`. Behaviour is identical — 10 total attempts, 9 × 50ms sleeps between them, a
persistent `PermissionError` still propagates — but every branch is now reachable and tested.
Atomicity (temp-file + `os.replace`) and the Windows retry invariant are preserved.
**Impact / Risk:** None functional. Covered by `test_atomic_write_retries_then_succeeds` and
`test_atomic_write_gives_up_after_retries`.
**Outcome:** tracker.py at 100% line+branch coverage.

### Entry 5

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Add a pytest suite at 100% coverage (user-requested).

**Context:** The TUI test harness (`App.run_test()`) crashed on teardown with `'str' object has
no attribute '_close_messages'`. `DocketApp.__init__` stored the registry path in
`self._registry`, shadowing Textual's internal `App._registry` (the node set Textual iterates on
close). Masked in normal use because the process exits on quit, but a real latent bug.
**Decision:** Renamed the instance attribute to `self._registry_path` (3 occurrences in tui.py).
No behaviour change to docket; removes the framework-internal collision.
**Impact / Risk:** None — purely an internal rename. Enables the TUI to be driven under the
Textual test harness.
**Outcome:** tui.py at 100% coverage; clean app teardown.

### Entry 6

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** Implement v2 plans (ITER_01_v2 config layering, ITER_02_v2 init/doctor/schema).

**Context:** `discover_repos` in ITER_02_v2 §04 derives the project name from `repo.name`
(unresolved). When `docket init --scan .` is run, the discovered repo at the scan root is
`Path(".")`, whose `.name` is `""` — an empty name that `load_registry` then rejects as
"missing 'name'". The plan also builds the `~`-relative path with `f"~/{p.relative_to(home)}"`,
which on Windows stringifies with backslashes.
**Decision:** Resolve the repo path first and take the name from the resolved path
(`p.name`), and emit the `~`-relative path with `.as_posix()`. For the normal `--scan ~/code`
case the names are identical to the plan's; only the degenerate "." root and the path separators
change. Strictly more robust, never worse; keeps generated configs portable and valid.
**Impact / Risk:** None negative. `init --scan .` now yields a valid non-empty name and
forward-slash paths.
**Outcome:** Verified via `docket init --scan . --dry-run`.

### Entry 7

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-20T00:00:00Z
**Task:** "CI updated accordingly" (part of the v2 goal).

**Context:** The goal asked for CI to be updated for the v2 work but did not specify how.
`docket doctor` is positioned in ITER_02_v2 §04 as a CI gate, but its `claude_bin` PATH check
and per-project path checks fail in CI (no `claude`, project paths are local). Making it a hard
gate would red-X every CI run.
**Decision:** Keep the existing lint + test(100% coverage) jobs and add a single packaging
smoke step `uv run docket init --dry-run` to the test job. It exercises `_schema_path()` /
`importlib.resources` resolution of the shipped schema end to end — the real packaging risk that
unit tests (which may patch the path) can miss — and exits 0 without needing `claude`.
**Impact / Risk:** Minimal; one extra fast step. Did not wire `docket doctor` into CI for the
reason above.
**Outcome:** CI stays green; packaging of the schema asset is smoke-tested.
