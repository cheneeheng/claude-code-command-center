"""Shared fixtures for the roundtable test suite."""

from __future__ import annotations

import json
import subprocess
import threading
from pathlib import Path

import pytest

from roundtable import locks, registry, sessions
from roundtable.registry import Project


@pytest.fixture(autouse=True)
def _clean_slate(monkeypatch):
    """Empty per-project lock table + no roundtable env vars leaking in."""
    monkeypatch.setattr(locks, "_locks", {})
    monkeypatch.setattr(locks, "_holders", {})
    monkeypatch.setattr(locks, "_guard", threading.Lock())
    monkeypatch.setattr(locks, "rounds_lock", threading.Lock())
    monkeypatch.delenv("C4_ROUNDTABLE_REGISTRY", raising=False)
    monkeypatch.delenv("C4_ROUNDTABLE_HOME", raising=False)
    yield


@pytest.fixture
def project(tmp_path) -> Project:
    """A Project rooted at a temp dir with an empty planning/ tree (no git)."""
    root = tmp_path / "repo"
    (root / ".agents_workspace" / "planning").mkdir(parents=True)
    return Project(name="repo", path=str(root))


def _git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", *args], cwd=repo, capture_output=True, text=True, check=True
    )
    return proc.stdout.strip()


@pytest.fixture
def gitrepo(project) -> Project:
    """The `project` fixture upgraded to a real git repo with one commit."""
    root = Path(project.path)
    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "user.email", "t@example.com")
    _git(root, "config", "user.name", "tester")
    (root / "README.md").write_text("# fixture\n", encoding="utf-8")
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "init")
    return project


def write_plan(project: Project, slug: str, body: str = "# plan\n") -> Path:
    """Create a plan markdown file at planning/<slug>.md."""
    md = Path(project.path) / project.planning_dir / f"{slug}.md"
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
    """A .roundtable.json registry referencing `project`; returns its path."""
    reg = tmp_path / "reg.json"
    reg.write_text(
        json.dumps({"projects": [{"name": project.name, "path": project.path}]}),
        encoding="utf-8",
    )
    return str(reg)


@pytest.fixture
def state_dir(tmp_path) -> Path:
    """An app state dir (~/.roundtable stand-in)."""
    d = tmp_path / "state"
    d.mkdir()
    return d


@pytest.fixture
def claude_on_path(monkeypatch):
    """Make resolve_bin / doctor's claude check pass — CI has no real `claude`."""
    monkeypatch.setattr(sessions.shutil, "which", lambda b: f"/usr/bin/{b}")
    monkeypatch.setattr(
        registry.shutil, "which", lambda b: f"/usr/bin/{b}", raising=True
    )
    yield


# --- fake subprocess ---------------------------------------------------------------


class FakeProc:
    """Stand-in for subprocess.Popen (sessions.spawn_claude is the only spawner)."""

    def __init__(self, lines: list[str], returncode: int = 0, hang: bool = False):
        self._lines = list(lines)
        self.returncode = returncode
        self.stdin = _FakeStdin()
        self.stdout = _FakeStdout(self._lines, hang)
        self.terminated = False
        self.killed = False
        self._hang = hang

    def wait(self, timeout=None):
        return self.returncode

    def terminate(self):
        self.terminated = True
        self.stdout.release()

    def kill(self):
        self.killed = True
        self.stdout.release()


class _FakeStdin:
    def __init__(self):
        self.written = ""
        self.closed = False

    def write(self, data):
        self.written += data

    def close(self):
        self.closed = True


class _FakeStdout:
    """Iterates canned lines; optionally blocks after them until released (so a
    'stop' can arrive while the turn is mid-stream)."""

    def __init__(self, lines, hang: bool):
        self._lines = lines
        self._hang = hang
        self._release = threading.Event()
        if not hang:
            self._release.set()

    def release(self):
        self._release.set()

    def __iter__(self):
        yield from self._lines
        self._release.wait(timeout=10)

    def close(self):
        pass


@pytest.fixture
def fake_popen(monkeypatch):
    """Patch spawn_claude (in sessions AND executor, which from-imports it) to
    return a FakeProc; returns the capture dict. Never touches the global
    subprocess module — git subprocess calls keep working."""

    def install(lines, returncode=0, hang=False, side_effect=None):
        captured = {"cmds": [], "procs": []}

        def fake(cmd, cwd, prompt):
            if side_effect is not None:
                raise side_effect
            proc = FakeProc(lines, returncode, hang)
            proc.stdin.write(prompt)
            proc.stdin.close()
            captured["cmds"].append(cmd)
            captured["procs"].append(proc)
            captured["cmd"] = cmd
            captured["proc"] = proc
            captured["kwargs"] = {"cwd": cwd}
            return proc

        monkeypatch.setattr("roundtable.sessions.spawn_claude", fake)
        monkeypatch.setattr("roundtable.executor.spawn_claude", fake)
        return captured

    return install


# Canned stream-json events.
def ev_init(session_id="sid-1", model="claude-sonnet-4-5"):
    return json.dumps(
        {
            "type": "system",
            "subtype": "init",
            "session_id": session_id,
            "model": model,
        }
    )


def ev_text(text="hello"):
    return json.dumps(
        {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}
    )


def ev_tool(name="Write", path="x.md"):
    return json.dumps(
        {
            "type": "assistant",
            "message": {
                "content": [
                    {"type": "tool_use", "name": name, "input": {"file_path": path}}
                ]
            },
        }
    )


def ev_result(cost=0.05, model_usage=None, usage=None, subtype="success"):
    ev = {"type": "result", "subtype": subtype, "total_cost_usd": cost}
    if model_usage is not None:
        ev["modelUsage"] = model_usage
    if usage is not None:
        ev["usage"] = usage
    return json.dumps(ev)


USAGE = {
    "input_tokens": 1000,
    "output_tokens": 500,
    "cache_creation_input_tokens": 100,
    "cache_read_input_tokens": 50,
}
