# Decision Log

### Entry 1

**Type:** Decision
**Mode:** Autonomous
**Timestamp:** 2026-06-15T21:58:00+08:00
**Task:** Add interactive skills (daily-lessons, daily-summary, weekly-lessons) replacing the `claude --print` cron triggers, which break under the new programmatic-credit limit.

**Context:** Two forks the user left unresolved:
1. The daily-lessons subagents run in parallel and share the meta-repo working dir. The `ceh-lessons-learned` skill writes to a fixed relative path (`docs/claude_logs/LESSONS_LEARNED.md`), so reusing it across parallel subagents would collide.
2. Where to stage the per-chat input files / manifest, and whether to use subagents for the weekly harvest.

**Decision:**
1. The daily-lessons SKILL.md embeds the lessons-learned methodology and instructs each subagent to write directly to its own unique output path, instead of invoking `ceh-lessons-learned`. This makes the fan-out parallel-safe. daily-summary was already parallel-safe (its prompt writes to a per-job Output path).
2. Staging goes in `$CLAUDE_META_DIR/.claude/scheduler-jobs/<scheduler>/` (input files + `manifest.json`); the prepare scripts add `.claude/scheduler-jobs/` to the meta repo `.gitignore` so a partial run is never committed. Weekly uses no subagents — it is a single analysis job, per the user.

**Impact / Risk:** The daily-lessons output format is now defined in SKILL.md rather than delegated to the `ceh-lessons-learned` skill; if that skill's format evolves, the SKILL.md must be updated to match. Low risk — format is stable and self-contained.

**Outcome:** Six prepare scripts (.sh + .ps1) and three SKILL.md files created; all pass syntax/parse checks and the no-work path was smoke-tested on both platforms.
