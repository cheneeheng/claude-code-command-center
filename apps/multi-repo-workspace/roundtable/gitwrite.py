"""Commit action — the app's ONLY git write, deliberately quarantined here.

No push, no branch operations, no --amend: commit is safe and locally reversible,
which is why it is the one write inside the MVP line (SKELETON_v5 repo-write policy).
"""

from __future__ import annotations

import subprocess
from typing import Any

from roundtable.gitinfo import GIT_TIMEOUT, GitError, git_env
from roundtable.locks import Conflict


def _run(repo: str, *args: str) -> str:
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=repo,
            env=git_env(repo),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=GIT_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GitError(str(exc)) from exc
    if proc.returncode != 0:
        raise GitError(proc.stderr.strip() or proc.stdout.strip() or "git failed")
    return proc.stdout.rstrip("\n")


def commit(repo: str, message: str) -> dict[str, Any]:
    """`git add -A` + `git commit -m MESSAGE` (argv, no shell); returns {head, subject}.

    Empty/whitespace message -> ValueError (400); nothing staged after add -A ->
    Conflict nothing_to_commit (409).
    """
    if not message or not message.strip():
        raise ValueError("commit message must not be empty")
    _run(repo, "add", "-A")
    if not _run(repo, "status", "--porcelain"):
        raise Conflict("nothing_to_commit", "working tree is clean")
    _run(repo, "commit", "-m", message.strip())
    head = _run(repo, "log", "-1", "--format=%H\x1f%s")
    commit_hash, subject = head.split("\x1f", 1)
    return {"head": commit_hash, "subject": subject}
