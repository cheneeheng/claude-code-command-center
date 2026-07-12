"""gitwrite: the one git write — commit guards and success shape."""

from __future__ import annotations

from pathlib import Path

import pytest

from roundtable import gitwrite
from roundtable.gitinfo import GitError
from roundtable.locks import Conflict


@pytest.mark.parametrize("message", ["", "   ", "\n"])
def test_empty_message_rejected(gitrepo, message):
    with pytest.raises(ValueError, match="must not be empty"):
        gitwrite.commit(gitrepo.path, message)


def test_nothing_to_commit(gitrepo):
    with pytest.raises(Conflict) as exc:
        gitwrite.commit(gitrepo.path, "msg")
    assert exc.value.code == "nothing_to_commit"


def test_commit_success(gitrepo):
    (Path(gitrepo.path) / "new.txt").write_text("hi\n", encoding="utf-8")
    out = gitwrite.commit(gitrepo.path, "  add new file  ")
    assert out["subject"] == "add new file"
    assert len(out["head"]) == 40


def test_git_failure_raises_giterror(tmp_path):
    with pytest.raises(GitError):
        gitwrite.commit(str(tmp_path / "not-a-dir"), "msg")


def test_git_error_in_plain_dir(tmp_path):
    with pytest.raises(GitError):
        gitwrite.commit(str(tmp_path), "msg")  # not a git repo -> nonzero rc


def test_commit_never_reaches_ancestor_repo(gitrepo):
    """A non-repo dir nested inside a repo must not commit to the ancestor."""
    nested = Path(gitrepo.path) / "nested"
    nested.mkdir()
    (nested / "f.txt").write_text("x", encoding="utf-8")
    with pytest.raises(GitError):
        gitwrite.commit(str(nested), "msg")
