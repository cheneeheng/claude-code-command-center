"""Shared fixtures for the docket test suite."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from docket import core


@pytest.fixture(autouse=True)
def _reset_locks(monkeypatch):
    """Each test starts with the per-project lock table empty (locks are
    process-global) and no DOCKET_REGISTRY leaking in from the environment."""
    monkeypatch.setattr(core, "_locks", {})
    monkeypatch.setattr(core, "_locks_guard", core.threading.Lock())
    monkeypatch.delenv("DOCKET_REGISTRY", raising=False)
    yield


@pytest.fixture(autouse=True)
def _claude_on_path(monkeypatch):
    """Make the claude_bin preflight (run_implement / doctor) pass by default — CI has
    no real `claude`. Tests of the 'not found' path override core.shutil.which."""
    monkeypatch.setattr(core.shutil, "which", lambda b: f"/usr/bin/{b}")
    yield


@pytest.fixture
def project(tmp_path) -> core.Project:
    """A Project rooted at a temp dir with an empty planning/ tree."""
    root = tmp_path / "repo"
    (root / ".agents_workspace" / "planning").mkdir(parents=True)
    return core.Project(name="repo", path=str(root))


def write_plan(project: core.Project, slug: str, body: str = "# plan\n") -> Path:
    """Create a plan markdown file at planning/<slug>.md."""
    md = Path(project.path) / ".agents_workspace" / "planning" / f"{slug}.md"
    md.parent.mkdir(parents=True, exist_ok=True)
    md.write_text(body, encoding="utf-8")
    return md


@pytest.fixture
def plan_file(project) -> str:
    """A single plan with a frontmatter title; returns its slug."""
    write_plan(project, "alpha", "---\ntitle: Alpha Plan\n---\n# body\n")
    return "alpha"


@pytest.fixture
def registry_file(tmp_path, project) -> str:
    """A projects.json registry referencing `project`; returns its path."""
    reg = tmp_path / "projects.json"
    reg.write_text(
        json.dumps(
            {
                "instruction_template": "Implement {path} now.",
                "projects": [{"name": project.name, "path": project.path}],
            }
        ),
        encoding="utf-8",
    )
    return str(reg)


class FakeProc:
    """Stand-in for subprocess.Popen used by run_implement tests."""

    def __init__(self, lines: list[str], returncode: int = 0):
        self._lines = list(lines)
        self.returncode = returncode
        self.stdin = _FakeStdin()
        self.stdout = _FakeStdout(self._lines)
        self.terminated = False
        self.killed = False

    def wait(self, timeout=None):
        return self.returncode

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True


class _FakeStdin:
    def __init__(self):
        self.written = ""
        self.closed = False

    def write(self, data):
        self.written += data

    def close(self):
        self.closed = True


class _FakeStdout:
    def __init__(self, lines):
        self._lines = lines

    def __iter__(self):
        return iter(self._lines)

    def close(self):
        pass


@pytest.fixture
def fake_popen_factory(monkeypatch):
    """Patch core.subprocess.Popen to return a FakeProc with given output/rc."""

    def install(lines, returncode=0):
        captured = {}

        def fake_popen(cmd, **kwargs):
            proc = FakeProc(lines, returncode)
            captured["cmd"] = cmd
            captured["kwargs"] = kwargs
            captured["proc"] = proc
            return proc

        monkeypatch.setattr(core.subprocess, "Popen", fake_popen)
        return captured

    return install
