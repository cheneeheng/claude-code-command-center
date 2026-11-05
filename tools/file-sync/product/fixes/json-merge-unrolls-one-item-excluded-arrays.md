---
schema: fix-record/v1
status: fixed
date: 2026-11-05
plan: product/plans/conhost-launcher.md
---

# json-merge turns an excluded one-item array into an object

**Symptom:** with `-ExcludePaths "statusLine.command,hooks.SessionStart"`, a sync whose destination
holds `"SessionStart": [ { "matcher": "startup", ... } ]` writes
`"SessionStart": { "matcher": "startup", ... }`, an object where Claude Code expects an array of
matcher groups. Seen on this machine: after one run of the settings sync task,
`jq '.hooks.SessionStart | type' ~/.claude/settings.json` printed `"object"`, and indexing it with
`[0]` failed (`Cannot index object with number`).

## Diagnosis

| Hypothesis | Refuted by | Result |
| ---------- | ---------- | ------ |
| The excluded value is read back unchanged, and the write corrupts it | `tests/json-merge.ps1` with a one-item array at the excluded path | confirmed the corruption: `actual: {"hooks":{"SessionStart":{"matcher":"startup",...}}}` for both a source with and without the key |
| The read unrolls the array | `return , $cur` in `Get-NestedValue` alone turning both cases green | confirmed: `ok   excluded one-item array stays an array`, and `2 failed` again with the fix stashed |

**Cause:** `tools/file-sync/sync-engine.ps1:62`: `Get-NestedValue` ended with `return $cur`.
PowerShell writes a returned array to the pipeline item by item, so a one-item array reaches the
caller as its single element, and `Set-NestedValue` then plants that element where the array was.
The existing tests excluded only strings (`statusLine.command`, a hook's `command`), so no test held
an array at the excluded path.

**Prediction:** `pwsh -NoProfile -File tests/json-merge.ps1` with the fix → `all passed`; with the
fix stashed → `2 failed`. Both seen.

## Fix

`Get-NestedValue` returns `, $cur`, which hands the value to the caller as one object, so an array
stays an array. A JSON `null` at the path is still not restored, as before.

**Tests:**

- `excluded one-item array stays an array` — protects: a one-item array at an excluded path keeps
  its shape when the source has it too; fails_when: the read unrolls arrays again; why_new: every
  earlier test excluded a string.
- `excluded one-item array is restored when the source lacks it` — protects: the same shape when
  the value is re-added to a merged object without it; fails_when: as above; why_new: as above.
- `excluded two-item array keeps both items` — protects: arrays of more than one item; fails_when:
  a fix that special-cases one item and wraps or flattens larger arrays; why_new: no array case
  existed.
- `excluded null value is not turned into an array` — protects: a JSON `null` at the path still
  restores nothing; fails_when: the comma wrap makes `null` a `[null]`; why_new: the fix changes the
  return of every read, so the null path needed pinning.

**Unverified:** none. The live sync task runs this checkout's engine, so it takes the fix once
`main` is pulled here.
