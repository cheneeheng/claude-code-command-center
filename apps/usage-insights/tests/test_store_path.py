from pathlib import Path

import pytest

from usage_insights import store

NEW = Path(".claude-command-center", "usage-insights")


@pytest.fixture
def home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.delenv("C4_USAGE_INSIGHTS_HOME", raising=False)
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    return tmp_path


def test_default_is_under_command_center(home: Path) -> None:
    assert store.store_path() == home / NEW / "usage.db"


def test_old_store_is_used_until_setup_moves_it(home: Path) -> None:
    (home / ".usage-insights").mkdir()
    assert store.store_path() == home / ".usage-insights" / "usage.db"


def test_new_store_wins_when_both_exist(home: Path) -> None:
    (home / ".usage-insights").mkdir()
    (home / NEW).mkdir(parents=True)
    assert store.store_path() == home / NEW / "usage.db"


def test_env_var_overrides(home: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    (home / ".usage-insights").mkdir()
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(home / "x"))
    assert store.store_path() == home / "x" / "usage.db"
