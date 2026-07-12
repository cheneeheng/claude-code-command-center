"""cli: argparse dispatch to serve / init / doctor."""

from __future__ import annotations

import roundtable.__main__  # noqa: F401  — covers the module-under-import lines
from roundtable import cli


def test_no_command_prints_help(capsys):
    assert cli.main([]) == 1
    assert "serve" in capsys.readouterr().out


def test_serve_dispatch(monkeypatch):
    import roundtable.server as server

    calls = {}

    def fake_run(port=None, registry_path=None):
        calls["args"] = (port, registry_path)
        return 0

    monkeypatch.setattr(server, "run_server", fake_run)
    assert cli.main(["--registry", "r.json", "serve", "--port", "9999"]) == 0
    assert calls["args"] == (9999, "r.json")


def test_init_dispatch(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    assert cli.main(["init"]) == 0
    assert "wrote" in capsys.readouterr().out
    assert (tmp_path / ".roundtable.json").is_file()


def test_init_error_path(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    assert cli.main(["init"]) == 0
    assert cli.main(["init"]) == 1  # no-clobber
    assert "error:" in capsys.readouterr().err


def test_init_output_flag(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert cli.main(["init", "--output", "custom.json"]) == 0
    assert (tmp_path / "custom.json").is_file()


def test_doctor_dispatch(registry_file, claude_on_path, capsys):
    assert cli.main(["--registry", registry_file, "doctor"]) == 0
    assert "project(s)" in capsys.readouterr().out
