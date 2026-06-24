"""Unit tests for CLI dispatch."""

import docket.__main__ as main_mod


def test_no_command_prints_help(capsys):
    rc = main_mod.main([])
    assert rc == 1
    assert "usage" in capsys.readouterr().out.lower()


def test_tui_dispatch(monkeypatch):
    called = {}

    def fake_tui(registry=None):
        called["registry"] = registry
        return 0

    monkeypatch.setattr("docket.tui.run_tui", fake_tui)
    assert main_mod.main(["--registry", "/r.json", "tui"]) == 0
    assert called["registry"] == "/r.json"


def test_serve_dispatch(monkeypatch):
    called = {}

    def fake_serve(port, registry):
        called["port"] = port
        called["registry"] = registry
        return 0

    monkeypatch.setattr("docket.server.run_server", fake_serve)
    assert main_mod.main(["serve", "--port", "9000"]) == 0
    assert called["port"] == 9000


def test_serve_dispatch_defaults_port_to_none(monkeypatch):
    called = {}

    def fake_serve(port, registry):
        called["port"] = port
        return 0

    monkeypatch.setattr("docket.server.run_server", fake_serve)
    assert main_mod.main(["serve"]) == 0
    assert called["port"] is None  # run_server falls back to Config.port


def test_init_dispatch(monkeypatch, capsys):
    called = {}

    def fake_init(**kw):
        called.update(kw)
        return "wrote out.json"

    monkeypatch.setattr("docket.core.cmd_init", fake_init)
    rc = main_mod.main(
        ["init", "--scan", "/r", "--output", "out.json", "--force", "--dry-run"]
    )
    assert rc == 0
    assert called == {
        "output": "out.json",
        "scan": "/r",
        "force": True,
        "merge": False,
        "dry_run": True,
    }
    assert "wrote out.json" in capsys.readouterr().out


def test_init_dispatch_handles_clobber_error(monkeypatch, capsys):
    def fake_init(**kw):
        raise FileExistsError("exists — pass --force")

    monkeypatch.setattr("docket.core.cmd_init", fake_init)
    assert main_mod.main(["init"]) == 1
    assert "error:" in capsys.readouterr().err


def test_doctor_dispatch(monkeypatch):
    monkeypatch.setattr("docket.core.cmd_doctor", lambda registry: 3)
    assert main_mod.main(["--registry", "/r.json", "doctor"]) == 3
