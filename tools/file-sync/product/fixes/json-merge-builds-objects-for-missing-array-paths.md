---
status: fixed
date: 2026-10-14
---

# json-merge writes an object where an array belongs when the source lacks an indexed exclude path

**Symptom:** syncing `settings.json` with `-ExcludePaths "hooks.PreToolUse[0].hooks[0].command"`
from a source whose `hooks` has no `PreToolUse` → the destination gets
`"PreToolUse":{"hooks":{"command":"bash ~/.claude/hooks/branch-guard.sh"}}`, an object Claude Code
rejects (it expects an array of matchers), so sessions using that config dir fail.

## Diagnosis

| Hypothesis | Refuted by | Result |
| ---------- | ---------- | ------ |
| The malformed hook was written by hand, not by the sync | The engine, run on temp files, producing the same shape | refuted: source `{"hooks":{"Stop":[]},"x":1}`, destination with a valid `PreToolUse` array, output `"PreToolUse":{"hooks":{"command":"bash ~/.claude/hooks/branch-guard.sh"}}` |
| The engine corrupts every indexed exclude path | A source that already has the `PreToolUse` array syncing cleanly | refuted: output `{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"DST"}]}]}}` |
| `Set-NestedValue` creates `{}` for a missing key even when the next step is an index, and the index guard does not notice | PowerShell refusing to index a single object | confirmed: `[pscustomobject]@{}` has `Count=1`, and `$o[0]` returns `$o` itself (`sameObj=True`) |

**Cause:** `tools/file-sync/sync-engine.ps1:71` and `:76`: when the source lacks `PreToolUse`,
`Set-NestedValue` adds the missing key as an empty object (line 71). The next step is the index
`[0]`. The guard on line 76 compares `0` with the object's `Count`, which PowerShell reports as 1
for any single object, so the guard passes and `$cur[0]` returns the object itself. The rest of the
path is then built from objects, so the destination value is re-planted as
`{"hooks":{"command":…}}` and drops `matcher` and `type`. On every later sync, `Get-NestedValue`
reads the same value back out of the broken shape (same `Count`/`[0]` behavior), so the corruption
persists.

On this machine `~/.claude/settings.json` has `"hooks": {}` and
`~/.claude_devcontainer/settings.json` had a branch-guard `PreToolUse` hook, so each sync from
`.claude` rewrote the devcontainer copy in the broken shape.

**Prediction:** a source with no `hooks` key at all must corrupt the destination the same way →
seen: `{"x":1,"hooks":{"PreToolUse":{"hooks":{"command":"DST"}}}}`.

## Fix

`Set-NestedValue` no longer creates a missing key that sits before the path's last array index,
and it treats an index on anything but an array as unresolvable. A destination value whose array
the source lacks is now dropped, matching the source, instead of being re-planted in the wrong
shape. Paths with no index, such as `statusLine.command`, still create their missing keys.

**Tests:** `tools/file-sync/tests/json-merge.ps1`, run by `.github/workflows/file-sync.yml`.

- `source without the indexed array adds no object in its place` — protects: a source with
  `hooks` but no `PreToolUse` syncs without inventing one; fails_when: a missing key before an
  index is created as an object again; why_new: file-sync had no tests, and array paths were added
  in `8e1dfcb` without one for a source missing the array.
- `source without the parent key adds nothing` — protects: no partial `hooks: {}` is left behind
  when the whole parent is missing; fails_when: keys before the index are created before the
  missing one is found; why_new: same gap.
- `source array element without the nested array adds nothing` — protects: an existing array
  element missing the inner `hooks` array stays untouched; fails_when: the inner key is created as
  an object; why_new: same gap.
- `source with the indexed array keeps the destination value` and `object-only path is still
  created when the source lacks it` — pin the behavior the fix must keep; they passed before and
  after.

**Unverified:** none for the engine. The live devcontainer `settings.json` was cleaned by hand
(the broken `PreToolUse` removed while the tasks were disabled), then one sync ran with result 0
and left both files identical apart from `statusLine`.
