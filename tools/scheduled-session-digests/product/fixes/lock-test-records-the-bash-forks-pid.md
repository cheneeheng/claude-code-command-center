---
schema: fix-record/v1
status: fixed
date: 2026-11-05
---

# The live-lock test sometimes records the bash fork's PID on Windows

**Symptom:** `bash tests/run.sh pwsh archive` on the Windows CI runner, intermittently →
`FAIL: live lock reported` and `FAIL: live lock: nothing archived`

## Diagnosis

| Hypothesis | Refuted by | Result |
| --- | --- | --- |
| The pwsh lock code (`src/lib.ps1` `Test-LockLive`) misjudges a live holder | the code is unchanged since 10-26, and the failures start 2026-11-05 15:15 | refuted: `git log -- tools/scheduled-session-digests` has no change since 990a1e6 (10-26) |
| The recorded start time and the later `Get-Process` disagree for one process | an immediate and a later read of one holder's PID and start time match | refuted locally: 8/8 loops gave equal `recorded` and `later` values |
| `/proc/<pid>/winpid`, read before the job execs, names the bash fork, which exits on exec | the pre-exec Windows PID is still alive after the exec | confirmed: `(sleep 1; exec sleep 60) &` gave pre-exec 72752, post-exec 57700, pre-exec process `GONE` (3/3) |

**Cause:** `tests/run.sh` `pid_for_ut`: it read `/proc/$1/winpid` right after `sleep 60 &`. On a
slow runner the fork has not exec'd `sleep` yet, so the lock names the fork's Windows process. That
process exits on exec, so the run sees a dead holder, takes the lock as stale, and archives.

**Prediction:** forcing a late exec, `(sleep 0.3; exec sleep 60) &`, makes
`bash tests/run.sh pwsh archive` fail locally every time → `passed 32, failed 2` with both
live-lock FAIL lines, 3/3.

## Fix

`pid_for_ut` now waits, for up to 10 s, until the job's `/proc/<pid>/cmdline` stops matching this
shell's, meaning it has exec'd, before it reads the Windows PID. The test keeps the 0.3 s late exec,
so the race happens on every run instead of only on slow runners.

**Tests:**

- `tests/run.sh` suite `archive`, the live-lock case with `(sleep 0.3; exec sleep 60) &` — protects:
  a lock held by a live process is reported and leaves nothing archived, under pwsh on Windows;
  fails_when: `pid_for_ut` reads the Windows PID before the exec again; why_new: the holder was
  `sleep 60 &`, which execs fast enough on a local machine that the race only showed on CI.

**Unverified:** the full Windows CI job, until the PR runs.
