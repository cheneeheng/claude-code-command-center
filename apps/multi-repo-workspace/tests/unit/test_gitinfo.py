"""gitinfo: git introspection (real fixture repos) + file browse/edit guards."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from roundtable import gitinfo
from tests.conftest import _git


def test_branch_and_detached(gitrepo):
    assert gitinfo.branch(gitrepo.path) == ("main", False)
    _git(Path(gitrepo.path), "checkout", "-q", "--detach")
    name, detached = gitinfo.branch(gitrepo.path)
    assert detached and name != "main"


def test_dirty_counts_untracked(gitrepo):
    assert gitinfo.dirty(gitrepo.path) == 0
    (Path(gitrepo.path) / "x.txt").write_text("x", encoding="utf-8")
    assert gitinfo.dirty(gitrepo.path) == 1


def test_ahead_behind_none_without_upstream(gitrepo):
    assert gitinfo.ahead_behind(gitrepo.path) is None


def test_ahead_behind_with_upstream(gitrepo, tmp_path):
    clone = tmp_path / "clone"
    subprocess.run(
        ["git", "clone", "-q", gitrepo.path, str(clone)],
        check=True,
        capture_output=True,
    )
    _git(clone, "config", "user.email", "t@example.com")
    _git(clone, "config", "user.name", "tester")
    (clone / "more.txt").write_text("m", encoding="utf-8")
    _git(clone, "add", "-A")
    _git(clone, "commit", "-qm", "ahead")
    assert gitinfo.ahead_behind(str(clone)) == (1, 0)


def test_last_commit_and_log(gitrepo):
    head = gitinfo.last_commit(gitrepo.path)
    assert head is not None and head["subject"] == "init"
    assert len(head["hash"]) == 40 and head["ts"] > 0
    assert gitinfo.log(gitrepo.path) == [head]


def test_last_commit_empty_repo(project, tmp_path):
    repo = tmp_path / "empty"
    repo.mkdir()
    _git(repo, "init", "-q")
    assert gitinfo.last_commit(str(repo)) is None


def test_parse_commits_skips_blank_lines():
    assert gitinfo._parse_commits("\n \n") == []


def test_diff_stat_patch_untracked(gitrepo):
    root = Path(gitrepo.path)
    (root / "README.md").write_text("# fixture\nchanged\n", encoding="utf-8")
    (root / "new.txt").write_text("n", encoding="utf-8")
    out = gitinfo.diff(gitrepo.path)
    assert "README.md" in out["stat"]
    assert "+changed" in out["patch"]
    assert out["untracked"] == ["new.txt"]
    assert out["truncated"] is False


def test_diff_truncated(gitrepo, monkeypatch):
    monkeypatch.setattr(gitinfo, "DIFF_CAP", 10)
    (Path(gitrepo.path) / "README.md").write_text(
        "# fixture\n" + "x" * 100, encoding="utf-8"
    )
    out = gitinfo.diff(gitrepo.path)
    assert out["truncated"] is True
    assert len(out["patch"].encode("utf-8")) <= 10


def test_run_oserror_and_timeout(gitrepo, tmp_path, monkeypatch):
    with pytest.raises(gitinfo.GitError):
        gitinfo.branch(str(tmp_path / "missing"))

    def timeout(*a, **k):
        raise subprocess.TimeoutExpired(cmd="git", timeout=10)

    monkeypatch.setattr(gitinfo.subprocess, "run", timeout)
    with pytest.raises(gitinfo.GitError):
        gitinfo.dirty(gitrepo.path)


def test_run_nonzero_rc(tmp_path):
    with pytest.raises(gitinfo.GitError):
        gitinfo.dirty(str(tmp_path))  # not a repo


def test_run_default_error_message(gitrepo, monkeypatch):
    def fail(*a, **k):
        return subprocess.CompletedProcess(a, returncode=1, stdout="", stderr="")

    monkeypatch.setattr(gitinfo.subprocess, "run", fail)
    with pytest.raises(gitinfo.GitError, match="git status failed"):
        gitinfo.dirty(gitrepo.path)


def test_repo_state_happy(gitrepo):
    state, err = gitinfo.repo_state(gitrepo.path)
    assert err is None
    assert state is not None
    assert state["branch"] == "main" and state["detached"] is False
    assert state["ahead"] is None and state["behind"] is None
    assert state["last_commit"]["subject"] == "init"


def test_repo_state_error(project):
    state, err = gitinfo.repo_state(project.path)  # dir exists, not a repo
    assert state is None and err


# --- tree / read_file / save_file ---------------------------------------------------


def test_tree_dirs_first_git_skipped(gitrepo):
    root = Path(gitrepo.path)
    (root / "zdir").mkdir()
    (root / "afile.txt").write_text("a", encoding="utf-8")
    entries = gitinfo.tree(gitrepo.path)
    names = [e["name"] for e in entries]
    assert ".git" not in names
    assert names.index("zdir") < names.index("afile.txt")
    zdir = next(e for e in entries if e["name"] == "zdir")
    assert zdir["is_dir"] is True and zdir["size"] == 0


def test_tree_subdir_and_missing(gitrepo):
    root = Path(gitrepo.path)
    (root / "sub").mkdir()
    (root / "sub" / "f.txt").write_text("f", encoding="utf-8")
    assert [e["name"] for e in gitinfo.tree(gitrepo.path, "sub")] == ["f.txt"]
    with pytest.raises(FileNotFoundError):
        gitinfo.tree(gitrepo.path, "nope")


def test_traversal_guard(gitrepo):
    with pytest.raises(ValueError, match="escapes repo"):
        gitinfo.tree(gitrepo.path, "..")
    with pytest.raises(ValueError, match="escapes repo"):
        gitinfo.read_file(gitrepo.path, "../outside.txt")


def test_read_file_happy(gitrepo):
    out = gitinfo.read_file(gitrepo.path, "README.md")
    assert out["content"].startswith("# fixture")  # \n or \r\n per platform text mode
    assert out["mtime"] > 0


def test_read_file_missing(gitrepo):
    with pytest.raises(FileNotFoundError):
        gitinfo.read_file(gitrepo.path, "ghost.txt")


def test_read_file_too_large(gitrepo, monkeypatch):
    monkeypatch.setattr(gitinfo, "FILE_READ_CAP", 4)
    with pytest.raises(gitinfo.FileTooLarge):
        gitinfo.read_file(gitrepo.path, "README.md")


def test_read_file_binary(gitrepo):
    (Path(gitrepo.path) / "bin.dat").write_bytes(b"ab\x00cd")
    with pytest.raises(gitinfo.BinaryFile):
        gitinfo.read_file(gitrepo.path, "bin.dat")


def test_save_new_file(gitrepo):
    mtime = gitinfo.save_file(gitrepo.path, "notes/new.md", "# hi\n", None)
    target = Path(gitrepo.path) / "notes" / "new.md"
    assert target.read_text(encoding="utf-8") == "# hi\n"
    assert mtime == target.stat().st_mtime_ns


def test_save_existing_roundtrip(gitrepo):
    current = gitinfo.read_file(gitrepo.path, "README.md")["mtime"]
    new_mtime = gitinfo.save_file(gitrepo.path, "README.md", "# v2\r\n", current)
    assert (Path(gitrepo.path) / "README.md").read_bytes() == b"# v2\r\n"
    assert new_mtime >= current


def test_save_stale_mtime(gitrepo):
    with pytest.raises(gitinfo.StaleFile) as exc:
        gitinfo.save_file(gitrepo.path, "README.md", "x", 12345)
    assert exc.value.mtime == (Path(gitrepo.path) / "README.md").stat().st_mtime_ns


def test_save_existing_with_null_expect_is_stale(gitrepo):
    with pytest.raises(gitinfo.StaleFile):
        gitinfo.save_file(gitrepo.path, "README.md", "x", None)


def test_save_vanished_file(gitrepo):
    with pytest.raises(gitinfo.StaleFile) as exc:
        gitinfo.save_file(gitrepo.path, "ghost.txt", "x", 12345)
    assert exc.value.mtime is None


def test_save_body_too_large(gitrepo, monkeypatch):
    monkeypatch.setattr(gitinfo, "FILE_WRITE_CAP", 4)
    with pytest.raises(gitinfo.FileTooLarge):
        gitinfo.save_file(gitrepo.path, "big.txt", "12345", None)


def test_save_directory_target(gitrepo):
    (Path(gitrepo.path) / "adir").mkdir()
    with pytest.raises(ValueError, match="is a directory"):
        gitinfo.save_file(gitrepo.path, "adir", "x", None)


def test_save_binary_target(gitrepo):
    (Path(gitrepo.path) / "bin.dat").write_bytes(b"\x00")
    with pytest.raises(gitinfo.BinaryFile):
        gitinfo.save_file(gitrepo.path, "bin.dat", "x", 1)
