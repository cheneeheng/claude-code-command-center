"""Read-only git introspection + repo file browsing/editing primitives.

Every git call is `subprocess.run([git, ...], cwd=repo, timeout=10)` with no shell; any
failure (missing git, not a repo, timeout) degrades to null fields plus a `git_error`
string on the payload — the board must render for a mis-registered repo, never 500.
The only filesystem write here is `save_file`, an explicit user action per the
repo-write policy (SKELETON_v5 §02).
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

from roundtable.registry import atomic_write_text

GIT_TIMEOUT = 10
DIFF_CAP = 1024 * 1024  # 1 MB patch cap
FILE_READ_CAP = 512 * 1024
FILE_WRITE_CAP = 1024 * 1024
_BINARY_PROBE = 8 * 1024


class GitError(Exception):
    """A git invocation failed (missing binary, not a repo, timeout, nonzero rc)."""


class BinaryFile(Exception):
    """The target file fails the text heuristic (NUL byte in the first 8 KB)."""


class FileTooLarge(Exception):
    """The file (read) or body (write) exceeds its size cap."""


class StaleFile(Exception):
    """expect_mtime does not match the on-disk state; carries the current mtime."""

    def __init__(self, mtime: int | None) -> None:
        super().__init__("file changed on disk")
        self.mtime = mtime


def _run(repo: str, *args: str) -> str:
    """Run one git command; return stripped stdout or raise GitError."""
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=repo,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=GIT_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GitError(str(exc)) from exc
    if proc.returncode != 0:
        raise GitError(proc.stderr.strip() or f"git {args[0]} failed")
    return proc.stdout.rstrip("\n")


def branch(repo: str) -> tuple[str, bool]:
    """(branch_name, detached). Detached HEAD reports the short hash + True."""
    name = _run(repo, "rev-parse", "--abbrev-ref", "HEAD")
    if name == "HEAD":  # detached
        return _run(repo, "rev-parse", "--short", "HEAD"), True
    return name, False


def dirty(repo: str) -> int:
    """`git status --porcelain` line count (untracked included)."""
    out = _run(repo, "status", "--porcelain")
    return len(out.splitlines())


def ahead_behind(repo: str) -> tuple[int, int] | None:
    """(ahead, behind) vs upstream; None when there is no upstream (not an error)."""
    try:
        out = _run(repo, "rev-list", "--left-right", "--count", "@{upstream}...HEAD")
    except GitError:
        return None
    behind_s, ahead_s = out.split()
    return int(ahead_s), int(behind_s)


def _parse_commits(out: str) -> list[dict[str, Any]]:
    """Split `%H%x1f%ct%x1f%s` lines (unit separator; no fragile `|` parsing)."""
    commits: list[dict[str, Any]] = []
    for line in out.splitlines():
        if not line.strip():
            continue
        commit_hash, ts, subject = line.split("\x1f", 2)
        commits.append({"hash": commit_hash, "ts": int(ts), "subject": subject})
    return commits


def last_commit(repo: str) -> dict[str, Any] | None:
    """{hash, ts, subject} of HEAD; None for a repo with no commits."""
    try:
        out = _run(repo, "log", "-1", "--format=%H%x1f%ct%x1f%s")
    except GitError:
        return None
    commits = _parse_commits(out)
    return commits[0] if commits else None


def log(repo: str, n: int = 30) -> list[dict[str, Any]]:
    """Recent commits, newest first."""
    out = _run(repo, "log", f"-{n}", "--format=%H%x1f%ct%x1f%s")
    return _parse_commits(out)


def diff(repo: str) -> dict[str, Any]:
    """Working-tree diff: {stat, patch, untracked, truncated}. Patch capped at 1 MB."""
    stat = _run(repo, "diff", "--stat")
    patch = _run(repo, "diff")
    truncated = len(patch.encode("utf-8")) > DIFF_CAP
    if truncated:
        patch = patch.encode("utf-8")[:DIFF_CAP].decode("utf-8", errors="replace")
    untracked_out = _run(repo, "ls-files", "--others", "--exclude-standard")
    untracked = [ln for ln in untracked_out.splitlines() if ln.strip()]
    return {
        "stat": stat,
        "patch": patch,
        "untracked": untracked,
        "truncated": truncated,
    }


def repo_state(repo: str) -> tuple[dict[str, Any] | None, str | None]:
    """The board's RepoState: (state, git_error). Never raises."""
    try:
        name, detached = branch(repo)
        state: dict[str, Any] = {
            "branch": name,
            "detached": detached,
            "dirty_count": dirty(repo),
        }
    except GitError as exc:
        return None, str(exc)
    ab = ahead_behind(repo)
    state["ahead"], state["behind"] = ab if ab is not None else (None, None)
    state["last_commit"] = last_commit(repo)
    return state, None


# --- repo filesystem: tree / file read / file save ------------------------------


def resolve_inside(repo: str, rel: str) -> Path:
    """Path-traversal guard: REL resolved must stay inside the repo root, else ValueError."""
    root = os.path.realpath(repo)
    target = os.path.realpath(os.path.join(root, rel))
    if target != root and not target.startswith(root + os.sep):
        raise ValueError(f"path escapes repo: {rel!r}")
    return Path(target)


def tree(repo: str, rel: str = "") -> list[dict[str, Any]]:
    """One directory level (dirs first, `.git` skipped): [{name, is_dir, size}]."""
    target = resolve_inside(repo, rel)
    if not target.is_dir():
        raise FileNotFoundError(f"not a directory: {rel!r}")
    entries: list[dict[str, Any]] = []
    with os.scandir(target) as it:
        for entry in it:
            if entry.name == ".git":
                continue
            is_dir = entry.is_dir(follow_symlinks=False)
            entries.append(
                {
                    "name": entry.name,
                    "is_dir": is_dir,
                    "size": 0 if is_dir else entry.stat(follow_symlinks=False).st_size,
                }
            )
    entries.sort(key=lambda e: (not e["is_dir"], str(e["name"]).lower()))
    return entries


def _is_binary(data: bytes) -> bool:
    return b"\x00" in data[:_BINARY_PROBE]


def read_file(repo: str, rel: str) -> dict[str, Any]:
    """{content, mtime} for a text file. 512 KB cap; NUL in the first 8 KB -> BinaryFile."""
    target = resolve_inside(repo, rel)
    if not target.is_file():
        raise FileNotFoundError(f"no such file: {rel!r}")
    if target.stat().st_size > FILE_READ_CAP:
        raise FileTooLarge(f"file exceeds {FILE_READ_CAP} bytes")
    data = target.read_bytes()
    if _is_binary(data):
        raise BinaryFile(rel)
    return {
        "content": data.decode("utf-8", errors="replace"),
        "mtime": target.stat().st_mtime_ns,
    }


def save_file(repo: str, rel: str, content: str, expect_mtime: int | None) -> int:
    """Optimistic-concurrency text-file save; returns the new mtime_ns.

    Guards (data-loss protection, never simplified away): traversal check, 1 MB cap
    (FileTooLarge), no directory targets, no binary targets (BinaryFile), and
    expect_mtime must match the on-disk st_mtime_ns (StaleFile carries the current
    mtime; the client re-fetches and re-applies — the server never merges). A new
    file is created when expect_mtime is None and no file exists.
    """
    target = resolve_inside(repo, rel)
    if len(content.encode("utf-8")) > FILE_WRITE_CAP:
        raise FileTooLarge(f"body exceeds {FILE_WRITE_CAP} bytes")
    if target.is_dir():
        raise ValueError(f"target is a directory: {rel!r}")
    if target.is_file():
        if _is_binary(target.read_bytes()):
            raise BinaryFile(rel)
        current = target.stat().st_mtime_ns
        if expect_mtime is None or expect_mtime != current:
            raise StaleFile(current)
    elif expect_mtime is not None:
        raise StaleFile(None)  # expected an existing file; it vanished
    # UTF-8 exactly as received; no newline normalization.
    atomic_write_text(target, content)
    return target.stat().st_mtime_ns
