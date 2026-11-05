---
schema: fix-record/v1
status: fixed
date: 2026-11-05
plan: product/plans/session-title-hook.md
---

# `/clear` keeps the hook's own old title instead of a new dated one

**Symptom:** `bash tests/smoke.sh` → `FAIL: sh/bash/startup: kept its own old title: ''`

## Diagnosis

Cause known from the report: `/clear` passes the old session's title in `session_title`, and the
hook skipped every input with a `session_title`, including its own startup title.

**Cause:** `session-name-date-prefixer-setup.sh` and `.ps1`, the hook command's skip test: it
treated any `session_title` as a user name, so the title `/clear` inherited blocked the rename.

**Prediction:** `bash tests/smoke.sh` with the fix stashed → the same FAIL line, seen.

## Fix

Both hook commands now skip only a `session_title` that is not in the hook's own
`<leaf>-<10 digits>` form, so the inherited auto title is replaced and a `--name` or `/rename`
title is kept.

**Tests:**

- `tests/smoke.sh`, the `my-proj-0001010000` case — protects: the hook's own old title is
  replaced on `startup` and `clear`, in bash, pwsh and Windows PowerShell; fails_when: the skip test
  treats every `session_title` as a user name again; why_new: the smoke only fed no title or a
  custom one, never the inherited auto title.

**Unverified:** a live `/clear` in Claude Code. The smoke feeds the hook the input the report
describes, it does not start Claude Code.
