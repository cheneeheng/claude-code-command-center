"""TUI tests driven through Textual's async test harness (subprocess mocked)."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from docket import core, tracker, tui
from docket.tui import DocketApp
from tests.conftest import write_plan


@pytest.fixture
def tui_registry(project, tmp_path):
    """Registry file + two plans; returns (registry_path, project)."""
    write_plan(project, "alpha", "---\ntitle: Alpha\n---\n# body\n")
    write_plan(project, "beta")
    reg = tmp_path / "projects.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "repo", "path": project.path}]}),
        encoding="utf-8",
    )
    return str(reg), project


def _log_spy(app, monkeypatch):
    msgs: list[str] = []
    log = app.query_one("#log", tui.RichLog)
    monkeypatch.setattr(log, "write", lambda m: msgs.append(str(m)))
    return msgs


def _ok_run(returncode=0, raises=None):
    def fake(project, slug, instruction, *, on_spawn=None):
        if on_spawn:
            on_spawn(SimpleNamespace(returncode=returncode))
        if raises:
            raise raises
        yield f"▸ work on {slug}"

    return fake


# --- mount --------------------------------------------------------------------


async def test_mount_populates_tree_and_resets_stale(tui_registry):
    reg, project = tui_registry
    tracker.set_status(project, "alpha", "running", trigger="headless")  # stale
    app = DocketApp(registry=reg)
    async with app.run_test():
        assert app._projects[0].name == "repo"
        # on_mount called reset_stale_runs, which flipped the stale plan back to ready
        assert tracker.read_record(project, "alpha")["status"] == "ready"
        tree = app.query_one("#tree", tui.Tree)
        assert tree.root.children  # project node present


async def test_mount_empty_shows_no_projects(monkeypatch):
    monkeypatch.setattr(
        core, "load_registry", lambda registry: core.Config(port=8765, projects=[])
    )
    monkeypatch.setattr(
        core, "registry_search_paths", lambda registry: ["/a/projects.json"]
    )
    app = DocketApp(registry=None)
    async with app.run_test():
        labels = [str(n.label) for n in app.query_one("#tree", tui.Tree).root.children]
        assert any("no projects" in s for s in labels)
        assert any("searched" in s for s in labels)


# --- plan selection -----------------------------------------------------------


async def test_select_plan_renders_body(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.on_tree_node_highlighted(
            SimpleNamespace(node=SimpleNamespace(data=("repo", "alpha")))
        )
        view = app.query_one("#plan-view", tui.Static)
        assert "Alpha" in str(view.render())


async def test_highlight_node_without_data_is_noop(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.on_tree_node_highlighted(SimpleNamespace(node=SimpleNamespace(data=None)))
        assert app._current is None


async def test_highlight_missing_plan_logs(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        app.on_tree_node_highlighted(
            SimpleNamespace(node=SimpleNamespace(data=("repo", "ghost")))
        )
        assert any("ghost" in m for m in msgs)


# --- manual actions -----------------------------------------------------------


async def test_run_myself_copies_and_logs(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app._current = ("repo", "alpha")
        msgs = _log_spy(app, monkeypatch)
        monkeypatch.setattr(app, "copy_to_clipboard", lambda body: None)
        app.action_run_myself()
        assert any("copied" in m for m in msgs)
        assert any("claude -p" in m for m in msgs)


async def test_run_myself_clipboard_failure_logs(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app._current = ("repo", "alpha")
        msgs = _log_spy(app, monkeypatch)

        def boom(_):
            raise RuntimeError("no clipboard")

        monkeypatch.setattr(app, "copy_to_clipboard", boom)
        app.action_run_myself()
        assert any("unavailable" in m for m in msgs)


async def test_run_myself_no_current_is_noop(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.action_run_myself()  # _current is None -> returns


async def test_mark_and_reopen(tui_registry, project):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app._current = ("repo", "alpha")
        app.action_mark()
        assert tracker.read_record(project, "alpha")["status"] == "implemented"
        app.action_reopen()
        assert tracker.read_record(project, "alpha")["status"] == "ready"


async def test_manual_no_current_is_noop(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.action_mark()  # no current -> returns


async def test_manual_illegal_transition_logs(tui_registry, project, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        # set running *after* mount, else reset_stale_runs flips it back to ready
        tracker.set_status(project, "alpha", "running", trigger="headless")
        app._current = ("repo", "alpha")
        msgs = _log_spy(app, monkeypatch)
        app.action_mark()  # running -> implemented via manual is illegal
        assert msgs and "alpha" in msgs[-1]


async def test_toggle_select_adds_and_removes(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.action_toggle_select()  # cursor on root (no data) -> noop
        tree = app.query_one("#tree", tui.Tree)
        node = next(
            n for n in tree.root.children[0].children if n.data == ("repo", "alpha")
        )
        tree.move_cursor(node)
        app.action_toggle_select()
        assert ("repo", "alpha") in app._selected
        app.action_toggle_select()
        assert ("repo", "alpha") not in app._selected


async def test_toggle_select_rejects_non_ready(tui_registry, project, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        tracker.set_status(project, "alpha", "implemented", trigger="manual")
        tree = app.query_one("#tree", tui.Tree)
        node = next(
            n for n in tree.root.children[0].children if n.data == ("repo", "alpha")
        )
        tree.move_cursor(node)
        msgs = _log_spy(app, monkeypatch)
        app.action_toggle_select()
        assert ("repo", "alpha") not in app._selected
        assert any("only ready plans" in m for m in msgs)


# --- headless run (worker) ----------------------------------------------------


async def test_implement_modal_enter_runs(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    captured = {}
    async with app.run_test() as pilot:
        app._current = ("repo", "alpha")
        monkeypatch.setattr(
            app, "_run_batch", lambda items: captured.setdefault("items", items)
        )
        app.action_implement()
        await pilot.pause()
        await pilot.press("enter")  # submit the pre-filled instruction
        await pilot.pause()
    assert captured["items"][0][:2] == ("repo", "alpha")


async def test_implement_modal_escape_cancels(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    called = {"n": 0}
    async with app.run_test() as pilot:
        app._current = ("repo", "alpha")
        monkeypatch.setattr(
            app, "_run_batch", lambda items: called.__setitem__("n", called["n"] + 1)
        )
        app.action_implement()
        await pilot.pause()
        await pilot.press("escape")
        await pilot.pause()
    assert called["n"] == 0


async def test_implement_no_current_is_noop(tui_registry):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app.action_implement()  # returns immediately


async def test_implement_non_ready_logs_and_skips(tui_registry, project, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        app._current = ("repo", "alpha")
        tracker.set_status(project, "alpha", "implemented", trigger="manual")
        msgs = _log_spy(app, monkeypatch)
        app.action_implement()  # implemented -> not runnable, no modal
        assert any("reopen to run again" in m for m in msgs)


async def test_implement_selected_nothing_logs(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        app.action_implement_selected()
        assert any("nothing selected" in m for m in msgs)


async def test_implement_selected_submits_batch(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    captured = {}
    async with app.run_test():
        app._selected = {("repo", "alpha"), ("repo", "beta")}
        monkeypatch.setattr(
            app, "_run_batch", lambda items: captured.setdefault("items", items)
        )
        app.action_implement_selected()
        assert len(captured["items"]) == 2
        assert app._selected == set()


async def test_run_batch_streams_to_completion(tui_registry, monkeypatch):
    reg, _ = tui_registry
    monkeypatch.setattr(core, "run_implement", _ok_run(returncode=0))
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        await app._run_batch([("repo", "alpha", "instr")]).wait()
        assert any("work on alpha" in m for m in msgs)


async def test_run_batch_nonzero_rc_breaks(tui_registry, monkeypatch):
    reg, _ = tui_registry
    monkeypatch.setattr(core, "run_implement", _ok_run(returncode=3))
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        await app._run_batch([("repo", "alpha", "i"), ("repo", "beta", "i")]).wait()
        assert any("batch stopped (rc=3)" in m for m in msgs)


async def test_run_batch_exception_breaks(tui_registry, monkeypatch):
    reg, _ = tui_registry
    monkeypatch.setattr(core, "run_implement", _ok_run(raises=RuntimeError("locked")))
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        await app._run_batch([("repo", "alpha", "i")]).wait()
        assert any("locked" in m for m in msgs)


# --- stop ---------------------------------------------------------------------


async def test_stop_with_active_proc(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        proc = SimpleNamespace(
            terminated=False, terminate=lambda: setattr(proc, "terminated", True)
        )
        app._proc = proc
        app.action_stop()
        assert proc.terminated
        assert any("stop requested" in m for m in msgs)


async def test_stop_without_proc(tui_registry, monkeypatch):
    reg, _ = tui_registry
    app = DocketApp(registry=reg)
    async with app.run_test():
        msgs = _log_spy(app, monkeypatch)
        app.action_stop()
        assert any("no active run" in m for m in msgs)


# --- run_tui entry point ------------------------------------------------------


def test_run_tui_invokes_app_run(monkeypatch):
    monkeypatch.setattr(DocketApp, "run", lambda self: None)
    assert tui.run_tui(registry="/r.json") == 0
