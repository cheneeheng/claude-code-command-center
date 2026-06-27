"""Unit tests for the server-side RunManager (batch orchestration)."""

import subprocess
from types import SimpleNamespace

import pytest

from docket import core, tracker
from tests.conftest import write_plan


def _fake_run_factory(returncode=0, raises=None):
    def fake(project, slug, instruction, *, on_spawn=None, run_id=None):
        proc = SimpleNamespace(returncode=returncode)
        if on_spawn:
            on_spawn(proc)
        if raises:
            raise raises
        yield f"line for {slug}"

    return fake


@pytest.fixture
def manager(project):
    write_plan(project, "alpha")
    write_plan(project, "beta")
    return core.RunManager([project])


def _drain(manager, run_id):
    return [item for item in manager.stream(run_id, keepalive=0.05)]


# --- submit validation --------------------------------------------------------


def test_submit_unknown_project(manager):
    with pytest.raises(ValueError, match="unknown project"):
        manager.submit([{"project": "nope", "slug": "alpha"}])


def test_submit_bad_slug(manager):
    with pytest.raises(ValueError):
        manager.submit([{"project": "repo", "slug": "../x"}])


def test_submit_non_runnable(manager, project):
    tracker.set_status(project, "alpha", "running", trigger="headless")
    with pytest.raises(ValueError, match="not runnable"):
        manager.submit([{"project": "repo", "slug": "alpha"}])


def test_set_projects_replaces_registry(project):
    mgr = core.RunManager([])
    mgr.set_projects([project])
    assert mgr._projects == {"repo": project}


# --- batch logic (driven synchronously) ---------------------------------------


def test_batch_all_done(manager, project, monkeypatch):
    monkeypatch.setattr(core, "run_implement", _fake_run_factory(returncode=0))
    runs = [
        core.Run(run_id="r1", project="repo", slug="alpha", instruction="i"),
        core.Run(run_id="r2", project="repo", slug="beta", instruction="i"),
    ]
    manager._run_project_batch(project, runs)
    assert [r.state for r in runs] == ["done", "done"]


def test_batch_stop_on_failure_skips_rest(manager, project, monkeypatch):
    monkeypatch.setattr(core, "run_implement", _fake_run_factory(returncode=1))
    runs = [
        core.Run(run_id="r1", project="repo", slug="alpha", instruction="i"),
        core.Run(run_id="r2", project="repo", slug="beta", instruction="i"),
    ]
    manager._run_project_batch(project, runs)
    assert runs[0].state == "failed"
    assert runs[1].state == "skipped"


def test_batch_run_stopped_midway_keeps_stopped_state(manager, project, monkeypatch):
    # simulate RunManager.stop() flipping the run to 'stopped' while it streams
    runs = [core.Run(run_id="r1", project="repo", slug="alpha", instruction="i")]

    def fake(prj, slug, instruction, *, on_spawn=None, run_id=None):
        runs[0].state = "stopped"  # external stop lands mid-iteration
        yield "partial"

    monkeypatch.setattr(core, "run_implement", fake)
    manager._run_project_batch(project, runs)
    assert runs[0].state == "stopped"  # batch must not overwrite it with done/failed


def test_batch_precondition_exception_marks_failed(manager, project, monkeypatch):
    monkeypatch.setattr(
        core, "run_implement", _fake_run_factory(raises=RuntimeError("locked"))
    )
    runs = [core.Run(run_id="r1", project="repo", slug="alpha", instruction="i")]
    manager._run_project_batch(project, runs)
    assert runs[0].state == "failed"
    # the error line is queued for the SSE consumer
    assert runs[0].queue.get_nowait() == "[docket] locked"


# --- submit + threads + stream integration ------------------------------------


def test_submit_runs_and_streams_to_end(manager, monkeypatch):
    monkeypatch.setattr(core, "run_implement", _fake_run_factory(returncode=0))
    runs = manager.submit([{"project": "repo", "slug": "alpha"}])
    assert len(runs) == 1
    events = _drain(manager, runs[0].run_id)
    assert ("data", "line for alpha") in events
    assert events[-1] == ("end", "done")


# --- stream -------------------------------------------------------------------


def test_stream_unknown_run_raises_eagerly(manager):
    with pytest.raises(KeyError):
        manager.stream("ghost")  # must raise before iteration (handler needs 404)


def test_stream_emits_keepalive_then_end(manager):
    run = core.Run(run_id="k1", project="repo", slug="alpha", instruction="i")
    manager._runs["k1"] = run
    gen = manager.stream("k1", keepalive=0.01)
    assert next(gen) == ("keepalive", None)  # queue empty -> timeout
    run.queue.put(core._SENTINEL)
    assert next(gen) == ("end", "queued")


# --- stop ---------------------------------------------------------------------


def test_stop_unknown_run_raises(manager):
    with pytest.raises(KeyError):
        manager.stop("ghost")


def test_stop_finished_run_rejected(manager):
    run = core.Run(
        run_id="d1", project="repo", slug="alpha", instruction="i", state="done"
    )
    manager._runs["d1"] = run
    with pytest.raises(ValueError, match="not stoppable"):
        manager.stop("d1")


def test_stop_terminates_running_proc(manager):
    proc = SimpleNamespace(
        terminated=False,
        killed=False,
        terminate=lambda: setattr(proc, "terminated", True),
        wait=lambda timeout: None,
        kill=lambda: setattr(proc, "killed", True),
    )
    run = core.Run(
        run_id="s1",
        project="repo",
        slug="alpha",
        instruction="i",
        state="running",
        proc=proc,
    )
    manager._runs["s1"] = run
    manager.stop("s1")
    assert run.state == "stopped"
    assert proc.terminated and not proc.killed


def test_stop_escalates_to_kill_on_timeout(manager):
    def waiter(timeout):
        raise subprocess.TimeoutExpired(cmd="claude", timeout=timeout)

    proc = SimpleNamespace(
        terminated=False,
        killed=False,
        terminate=lambda: setattr(proc, "terminated", True),
        wait=waiter,
        kill=lambda: setattr(proc, "killed", True),
    )
    run = core.Run(
        run_id="s2",
        project="repo",
        slug="alpha",
        instruction="i",
        state="running",
        proc=proc,
    )
    manager._runs["s2"] = run
    manager.stop("s2")
    assert proc.killed


def test_stop_running_without_proc(manager):
    run = core.Run(
        run_id="s3",
        project="repo",
        slug="alpha",
        instruction="i",
        state="queued",
        proc=None,
    )
    manager._runs["s3"] = run
    manager.stop("s3")
    assert run.state == "stopped"
